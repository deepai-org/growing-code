#!/usr/bin/perl
# evolve.pl - the missing piece: evolve toten programs
#
# usage: perl evolve.pl [target] [generations] [--seed N] [--save file.tot]
#   targets: count, squares, fib, primes, evens, odds, powers
#   or just a number N for 1..N
#   default: count 1000
#
# the fitness function rewards generalization: programs that produce
# correct values BEYOND the target get bonus points, proving they
# found the algorithm, not just memorized the sequence.

use strict;
use warnings;

# --- target generators ---
# each returns N values of the sequence
my %GENERATORS = (
	count  => sub { my $n=shift; [1..$n] },
	squares=> sub { my $n=shift; [map {$_*$_} 1..$n] },
	fib    => sub { my $n=shift; my @f=(1,1); push @f,$f[-1]+$f[-2] while @f<$n; [@f[0..$n-1]] },
	primes => sub { my $n=shift; my @p; for(my $i=2;@p<$n;$i++){my $ok=1; for my $d(2..int(sqrt($i))){$ok=0,last if $i%$d==0} push @p,$i if $ok} \@p },
	evens  => sub { my $n=shift; [map {$_*2} 1..$n] },
	odds   => sub { my $n=shift; [map {$_*2-1} 1..$n] },
	powers => sub { my $n=shift; [map {2**$_} 0..$n-1] },
);

# parse flags from anywhere in @ARGV
my ($SEED, $SAVE);
my @args;
for(my $i=0; $i<@ARGV; $i++){
	if($ARGV[$i] eq '--seed'){ $SEED = $ARGV[++$i] }
	elsif($ARGV[$i] eq '--save'){ $SAVE = $ARGV[++$i] }
	else { push @args, $ARGV[$i] }
}

my $targ = $args[0] || 'count';
my $GENS = $args[1] || 1000;

srand($SEED) if defined $SEED;

my $generator;
my @TARGET;
my @EXTENDED;  # longer version for generalization testing
my $TRAIN_LEN;

if($GENERATORS{$targ}){
	$generator = $GENERATORS{$targ};
	$TRAIN_LEN = {count=>10, squares=>6, fib=>8, primes=>6, evens=>5, odds=>5, powers=>6}->{$targ};
	@TARGET = @{$generator->($TRAIN_LEN)};
	@EXTENDED = @{$generator->($TRAIN_LEN + 10)};  # 10 extra values to test generalization
} elsif($targ =~ /^\d+$/){
	$TRAIN_LEN = $targ;
	@TARGET = (1..$targ);
	@EXTENDED = (1..$targ+10);
	$generator = sub { [1..$_[0]] };
} else {
	die "unknown target '$targ'\ntargets: ".join(", ",sort keys %GENERATORS).", or a number N\n";
}

my $POP = 150;
my $MRATE = 0.06;
my $GROW = 0.03;
my $ELITE = 5;
my $TSTEPS = 10000;
my $INIT_GLEN = 24;
my $MAX_GLEN = 80;

my @OPS = qw(if ifnot up down print add sub mul inc dec mod zero setv setc mark stop);

# --- genome to instructions ---
sub decode {
	my @g = @{$_[0]};
	my @out;
	for(my $i=0; $i<$#g; $i+=2){
		push @out, [$OPS[$g[$i] % 15], $g[$i+1] % 10];
	}
	return @out;
}

# --- interpreter ---
sub run {
	my ($ins_ref, $max_out) = @_;
	my @ins = @$ins_ref;
	$max_out //= 51;
	my %v;
	my $acc = 0;
	my $pc = 0;
	my @out;
	my $steps = 0;
	while($pc >= 0 && $pc <= $#ins && $steps < $TSTEPS){
		$steps++;
		my ($op, $n) = @{$ins[$pc]};
		if($op eq 'stop'){ last }
		elsif($op eq 'zero'){ $v{$n}=0 }
		elsif($op eq 'mark'){ $acc=$n }
		elsif($op eq 'setc'){ $v{$acc}=$n }
		elsif($op eq 'setv'){ $v{$acc}=$v{$n}//0 }
		elsif($op eq 'add') { $v{$acc}=($v{$acc}//0)+($v{$n}//0) }
		elsif($op eq 'sub') { $v{$acc}=($v{$acc}//0)-($v{$n}//0) }
		elsif($op eq 'mul') { $v{$acc}=($v{$acc}//0)*($v{$n}//0) }
		elsif($op eq 'div') { $v{$acc}=($v{$n}//0) ? int(($v{$acc}//0)/$v{$n}) : 0 }
		elsif($op eq 'mod') { $v{$acc}=($v{$n}//0) ? ($v{$acc}//0)%$v{$n} : 0 }
		elsif($op eq 'inc') { $v{$n}=($v{$n}//0)+1 }
		elsif($op eq 'dec') { $v{$n}=($v{$n}//0)-1 }
		elsif($op eq 'print'){ push @out, ($v{$n}//0); return @out if @out >= $max_out }
		elsif($op eq 'if')  { if(($v{$n}//0)==0){ $pc+=2; next } }
		elsif($op eq 'ifnot'){if(($v{$n}//0)!=0){ $pc+=2; next } }
		elsif($op eq 'up'){
			my $s=$pc; my $r=$n;
			if($r==0){next}
			while($r>0){ $s--; last if $s<0; $r-- if $ins[$s][0] eq 'mark' }
			if($r==0){ $pc=$s; next }
		}
		elsif($op eq 'down'){
			my $s=$pc; my $r=$n;
			if($r==0){next}
			while($r>0){ $s++; last if $s>$#ins; $r-- if $ins[$s][0] eq 'mark' }
			if($r==0){ $pc=$s; next }
		}
		$pc++;
	}
	return @out;
}

# --- fitness ---
sub fitness {
	my ($out_ref, $glen) = @_;
	my @out = @$out_ref;
	my $f = 0;

	# base: match the target
	$f += 1 if @out > 0;
	for my $i (0..$#TARGET){
		if($i < @out){
			my $d = abs($out[$i] - $TARGET[$i]);
			$f += $d==0 ? 10 : 10/(1+$d);
		}
	}

	# generalization bonus: correct values beyond the target
	# this is where memorization fails and real algorithms shine
	for my $i ($TRAIN_LEN..$#EXTENDED){
		if($i < @out){
			my $d = abs($out[$i] - $EXTENDED[$i]);
			$f += $d==0 ? 15 : 5/(1+$d);  # extra reward for generalization
		}
	}

	# penalty for excess output beyond what we can check
	my $excess = @out - @EXTENDED;
	$f -= $excess * 0.5 if $excess > 0;

	# parsimony: slightly prefer shorter programs
	$f -= $glen * 0.02;

	return $f;
}

# --- GA ops ---
sub rg { [map { int rand 256 } 1..$INIT_GLEN] }

sub mutate {
	my ($genome, $rate) = @_;
	$rate //= $MRATE;
	my @g = @$genome;
	for(@g){ $_ = int rand 256 if rand() < $rate }
	if(rand() < $GROW && @g < $MAX_GLEN){
		my $pos = 2 * int(rand(@g/2 + 1));
		splice @g, $pos, 0, int(rand(256)), int(rand(256));
	}
	if(rand() < $GROW && @g > 4){
		my $pos = 2 * int(rand(@g/2));
		splice @g, $pos, 2;
	}
	return \@g;
}

sub cross {
	my ($a,$b) = @_;
	my $pa = 2*int(rand(@$a/2)); $pa = 2 if $pa == 0;
	my $pb = 2*int(rand(@$b/2)); $pb = 2 if $pb == 0;
	my @child = (@{$a}[0..$pa-1], @{$b}[$pb..$#$b]);
	splice @child, $MAX_GLEN if @child > $MAX_GLEN;
	return \@child;
}

sub tourney {
	my ($pop,$fit) = @_;
	my $b = int rand @$pop;
	for(1..4){ my $i=int rand @$pop; $b=$i if $fit->[$i]>$fit->[$b] }
	return $b;
}

# --- main ---
my @pop = map { rg() } 1..$POP;
my $best_f = -999;
my $best_g;

my $target_str = join(', ',@TARGET);
my $ext_str = join(', ', @EXTENDED[$TRAIN_LEN..$#EXTENDED]);
print "target:  [$target_str]\n";
print "bonus:   [$ext_str]  (generalization test)\n";
print "pop=$POP gens=$GENS";
print "  seed=$SEED" if defined $SEED;
print "\n\n";

# stagnation tracking
my $STAG_THRESH = 50;  # generations without improvement before boosting
my $stag_count = 0;
my $stag_kicks = 0;
my $peak_gen = 0;
my $first_fit;
my $cur_mrate = $MRATE;

for my $gen (1..$GENS){
	my @fit;
	for my $g (@pop){
		my @ins = decode($g);
		my @out = run(\@ins, scalar @EXTENDED + 20);
		push @fit, fitness(\@out, scalar @$g);
	}

	my $bi = 0;
	for(1..$#fit){ $bi=$_ if $fit[$_]>$fit[$bi] }
	$first_fit //= $fit[$bi];

	if($fit[$bi] > $best_f){
		$best_f = $fit[$bi];
		$best_g = [@{$pop[$bi]}];
		$peak_gen = $gen;
		$stag_count = 0;
		$cur_mrate = $MRATE;  # reset to normal on improvement
		my @ins = decode($best_g);
		my @out = run(\@ins, scalar @EXTENDED + 20);
		my $os = @out ? join(",",@out) : "-";
		my $nb = scalar @{$best_g};
		my $matched = 0;
		for my $i (0..$#EXTENDED){ $matched++ if $i<@out && $out[$i]==$EXTENDED[$i] }
		printf "gen %4d  fit=%7.2f  len=%2db  match=%d/%d  out=[%s]\n",
			$gen, $best_f, $nb, $matched, scalar @EXTENDED, $os;
	}
	else {
		$stag_count++;
		if($stag_count == $STAG_THRESH){
			$cur_mrate = $MRATE * 3;
			$stag_kicks++;
			printf "gen %4d  ** stagnation kick #%d — mutation rate %.0f%% **\n",
				$gen, $stag_kicks, $cur_mrate*100;
		}
		if($gen % 100 == 0){
			my $avg = 0; $avg += $_ for @fit; $avg /= @fit;
			printf "gen %4d  best=%7.2f  avg=%6.2f\n", $gen, $best_f, $avg;
		}
	}

	# next gen
	my @si = sort { $fit[$b] <=> $fit[$a] } 0..$#pop;
	my @next;
	push @next, [@{$pop[$si[$_]]}] for 0..$ELITE-1;
	while(@next < $POP){
		my $a = tourney(\@pop,\@fit);
		my $b = tourney(\@pop,\@fit);
		push @next, mutate(cross($pop[$a],$pop[$b]), $cur_mrate);
	}
	@pop = @next;
}

# results
print "\n" . "="x60 . "\n";
my @ins = decode($best_g);
my @out = run(\@ins, scalar @EXTENDED + 20);
my $matched = 0;
for my $i (0..$#EXTENDED){ $matched++ if $i<@out && $out[$i]==$EXTENDED[$i] }
print "best program (fitness $best_f, ".scalar(@ins)." instructions):\n\n";
for(@ins){ print "  $_->[0] $_->[1]\n" }
print "\noutput:   [" . join(", ",@out) . "]\n";
print "expected: [" . join(", ",@EXTENDED) . "]\n";
print "matched $matched/".scalar(@EXTENDED)." values";
print " -- GENERALIZED!" if $matched > $TRAIN_LEN;
print " -- PERFECT ALGORITHM!" if $matched == scalar @EXTENDED;
print "\n";

# fitness summary
print "\n--- run summary ---\n";
printf "peak fitness %.2f at generation %d\n", $best_f, $peak_gen;
printf "improvement:  %.2f -> %.2f (+%.2f)\n", $first_fit, $best_f, $best_f - $first_fit;
printf "stagnation kicks: %d\n", $stag_kicks if $stag_kicks > 0;
print "\n";

# save best program as .tot file
if($SAVE){
	open my $fh, '>', $SAVE or die "can't write $SAVE: $!\n";
	for(@ins){ print $fh "$_->[0] $_->[1]\n" }
	close $fh;
	print "saved to $SAVE\n";
}
