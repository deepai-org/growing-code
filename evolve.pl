#!/usr/bin/perl
# evolve.pl - the missing piece: evolve toten programs
#
# usage: perl evolve.pl [target] [generations] [--seed N] [--save file.tot] [--stats file.csv]
#   targets: count, squares, fib, primes, evens, odds, powers
#   or just a number N for 1..N
#   or a comma-separated sequence like "1,4,9,16,25"
#   default: count 1000
#
# the fitness function rewards generalization: programs that produce
# correct values BEYOND the target get bonus points, proving they
# found the algorithm, not just memorized the sequence.

use strict;
use warnings;
use List::Util qw(min);

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
my ($SEED, $SAVE, $STATS, $ISLANDS);
my @args;
for(my $i=0; $i<@ARGV; $i++){
	if($ARGV[$i] eq '--seed'){ $SEED = $ARGV[++$i] }
	elsif($ARGV[$i] eq '--save'){ $SAVE = $ARGV[++$i] }
	elsif($ARGV[$i] eq '--stats'){ $STATS = $ARGV[++$i] }
	elsif($ARGV[$i] eq '--islands'){ $ISLANDS = $ARGV[++$i] }
	else { push @args, $ARGV[$i] }
}
$ISLANDS //= 1;

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
} elsif($targ =~ /^[\d,\s-]+$/ && $targ =~ /,/){
	# custom comma-separated sequence: "1,4,9,16,25"
	@TARGET = split /\s*,\s*/, $targ;
	$TRAIN_LEN = scalar @TARGET;
	# can't auto-extend a custom sequence, so just test what we have
	@EXTENDED = @TARGET;
} else {
	die "unknown target '$targ'\ntargets: ".join(", ",sort keys %GENERATORS).", a number N, or a comma-separated sequence\n";
}

my $POP = 150;
my $MRATE = 0.06;
my $GROW = 0.03;
my $ELITE = 5;
my $TSTEPS = 10000;
my $INIT_GLEN = 24;
my $MAX_GLEN = 80;

my @OPS = qw(if ifnot up down print add sub mul inc dec mod zero setv setc mark swap stop);

# --- genome to instructions ---
sub decode {
	my @g = @{$_[0]};
	my @out;
	for(my $i=0; $i<$#g; $i+=2){
		push @out, [$OPS[$g[$i] % 16], $g[$i+1] % 10];
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
		elsif($op eq 'swap'){ my $tmp=$v{$acc}//0; $v{$acc}=$v{$n}//0; $v{$n}=$tmp }
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

sub minimize {
	my @ins = @{$_[0]};
	my $baseline = join(',', run(\@ins, scalar @EXTENDED + 20));
	my $changed = 1;
	while($changed){
		$changed = 0;
		my $i = 0;
		while($i < @ins){
			my @try = @ins;
			splice @try, $i, 1;
			my $out = join(',', run(\@try, scalar @EXTENDED + 20));
			if($out eq $baseline){
				@ins = @try;
				$changed = 1;
			} else {
				$i++;
			}
		}
	}
	return @ins;
}

# --- main ---
my $ISLE_POP = int($POP / $ISLANDS);
my $MIGRATE = 25;  # migration interval in generations

my @islands;
for my $isle (0..$ISLANDS-1){
	push @islands, {
		pop        => [map { rg() } 1..$ISLE_POP],
		stag_count => 0,
		cur_mrate  => $MRATE,
	};
}

my $best_f = -999;
my $best_g;

my $target_str = join(', ',@TARGET);
my $ext_str = join(', ', @EXTENDED[$TRAIN_LEN..$#EXTENDED]);
print "target:  [$target_str]\n";
print "bonus:   [$ext_str]  (generalization test)\n";
print "pop=$POP gens=$GENS";
print "  islands=$ISLANDS" if $ISLANDS > 1;
print "  seed=$SEED" if defined $SEED;
print "\n\n";

# global tracking
my $STAG_THRESH = 50;
my $stag_kicks = 0;
my $peak_gen = 0;
my $first_fit;

# stats CSV
my $stats_fh;
if($STATS){
	open $stats_fh, '>', $STATS or die "can't write $STATS: $!\n";
	if($ISLANDS > 1){
		print $stats_fh "gen,island,best_fitness,avg_fitness,best_len,matched\n";
	} else {
		print $stats_fh "gen,best_fitness,avg_fitness,best_len,matched\n";
	}
}

for my $gen (1..$GENS){

	for my $isle_idx (0..$#islands){
		my $isle = $islands[$isle_idx];
		my @pop = @{$isle->{pop}};
		my @fit;
		for my $g (@pop){
			my @ins = decode($g);
			my @out = run(\@ins, scalar @EXTENDED + 20);
			push @fit, fitness(\@out, scalar @$g);
		}

		my $bi = 0;
		for(1..$#fit){ $bi=$_ if $fit[$_]>$fit[$bi] }
		$first_fit //= $fit[$bi];

		# write stats row
		if($stats_fh){
			my $avg = 0; $avg += $_ for @fit; $avg /= @fit;
			my @bi_ins = decode($pop[$bi]);
			my @bi_out = run(\@bi_ins, scalar @EXTENDED + 20);
			my $m = 0;
			for my $i (0..$#EXTENDED){ $m++ if $i<@bi_out && $bi_out[$i]==$EXTENDED[$i] }
			if($ISLANDS > 1){
				printf $stats_fh "%d,%d,%.4f,%.4f,%d,%d\n", $gen, $isle_idx, $fit[$bi], $avg, scalar @{$pop[$bi]}, $m;
			} else {
				printf $stats_fh "%d,%.4f,%.4f,%d,%d\n", $gen, $fit[$bi], $avg, scalar @{$pop[$bi]}, $m;
			}
		}

		# global best tracking
		if($fit[$bi] > $best_f){
			$best_f = $fit[$bi];
			$best_g = [@{$pop[$bi]}];
			$peak_gen = $gen;
			$isle->{stag_count} = 0;
			$isle->{cur_mrate} = $MRATE;
			my @ins = decode($best_g);
			my @out = run(\@ins, scalar @EXTENDED + 20);
			my $os = @out ? join(",",@out) : "-";
			my $nb = scalar @{$best_g};
			my $matched = 0;
			for my $i (0..$#EXTENDED){ $matched++ if $i<@out && $out[$i]==$EXTENDED[$i] }
			if($ISLANDS > 1){
				printf "gen %4d [%d]  fit=%7.2f  len=%2db  match=%d/%d  out=[%s]\n",
					$gen, $isle_idx, $best_f, $nb, $matched, scalar @EXTENDED, $os;
			} else {
				printf "gen %4d  fit=%7.2f  len=%2db  match=%d/%d  out=[%s]\n",
					$gen, $best_f, $nb, $matched, scalar @EXTENDED, $os;
			}
		}
		else {
			$isle->{stag_count}++;
			if($isle->{stag_count} == $STAG_THRESH){
				$isle->{cur_mrate} = $MRATE * 3;
				$stag_kicks++;
				if($ISLANDS > 1){
					printf "gen %4d [%d]  ** stagnation kick #%d — mutation rate %.0f%% **\n",
						$gen, $isle_idx, $stag_kicks, $isle->{cur_mrate}*100;
				} else {
					printf "gen %4d  ** stagnation kick #%d — mutation rate %.0f%% **\n",
						$gen, $stag_kicks, $isle->{cur_mrate}*100;
				}
			}
		}

		# next gen for this island
		my @si = sort { ($fit[$b]//0) <=> ($fit[$a]//0) } 0..$#pop;
		my @next;
		push @next, [@{$pop[$si[$_]]}] for 0..min($ELITE-1, $#pop);
		while(@next < $ISLE_POP){
			my $a = tourney(\@pop,\@fit);
			my $b = tourney(\@pop,\@fit);
			push @next, mutate(cross($pop[$a],$pop[$b]), $isle->{cur_mrate});
		}
		$isle->{pop} = \@next;
	}

	# periodic progress (not per-island)
	if($gen % 100 == 0){
		printf "gen %4d  best=%7.2f\n", $gen, $best_f;
	}

	# migration: best from island i -> island (i+1) % N, replacing worst
	if($ISLANDS > 1 && $gen % $MIGRATE == 0){
		# cache fitness for each island's population
		my @isle_fits;
		for my $i (0..$#islands){
			my @f;
			for my $g (@{$islands[$i]{pop}}){
				my @ins = decode($g);
				my @out = run(\@ins, scalar @EXTENDED + 20);
				push @f, fitness(\@out, scalar @$g);
			}
			push @isle_fits, \@f;
		}
		for my $i (0..$#islands){
			my $dst_idx = ($i + 1) % $ISLANDS;
			# best in source
			my $sf = $isle_fits[$i];
			my $sb = 0;
			for(1..$#$sf){ $sb=$_ if $sf->[$_]>$sf->[$sb] }
			# worst in destination
			my $df = $isle_fits[$dst_idx];
			my $dw = 0;
			for(1..$#$df){ $dw=$_ if $df->[$_]<$df->[$dw] }
			$islands[$dst_idx]{pop}[$dw] = [@{$islands[$i]{pop}[$sb]}];
		}
	}
}

# results
print "\n" . "="x60 . "\n";
my @ins = decode($best_g);
my $raw_count = scalar @ins;
@ins = minimize(\@ins);
my @out = run(\@ins, scalar @EXTENDED + 20);
my $matched = 0;
for my $i (0..$#EXTENDED){ $matched++ if $i<@out && $out[$i]==$EXTENDED[$i] }
my $min_note = $raw_count > @ins ? " (minimized from $raw_count)" : "";
print "best program (fitness $best_f, ".scalar(@ins)." instructions$min_note):\n\n";
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

if($stats_fh){
	close $stats_fh;
	print "stats saved to $STATS\n";
}
