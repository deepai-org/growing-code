#!/usr/bin/perl
# evolve.pl - the missing piece: evolve toten programs
#
# usage: perl evolve.pl [target] [generations]
#   targets: count (1..10), five (1..5), squares, fib, primes, evens
#   or just a number N for 1..N
#   default: count 1000

use strict;
use warnings;

# --- targets ---
my %TARGETS = (
	count  => [1..10],
	five   => [1..5],
	three  => [1..3],
	squares=> [map {$_*$_} 1..6],
	fib    => [1,1,2,3,5,8,13,21],
	primes => [2,3,5,7,11,13],
	evens  => [2,4,6,8,10],
	odds   => [1,3,5,7,9],
	powers => [1,2,4,8,16,32],
);

my $targ = $ARGV[0] || 'count';
my $GENS = $ARGV[1] || 1000;

my @TARGET;
if($TARGETS{$targ}){
	@TARGET = @{$TARGETS{$targ}};
} elsif($targ =~ /^\d+$/){
	@TARGET = (1..$targ);
} else {
	die "unknown target '$targ'\ntargets: ".join(", ",sort keys %TARGETS).", or a number N\n";
}

my $POP = 150;
my $MRATE = 0.06;
my $GROW = 0.03;     # chance to insert/delete a byte pair
my $ELITE = 5;
my $TSTEPS = 10000;
my $INIT_GLEN = 24;  # starting genome size
my $MAX_GLEN = 80;   # max genome size (40 instructions)

my @OPS = qw(if ifnot up down print add sub mul inc dec mod zero setv setc mark stop);

srand();

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
	my @ins = @_;
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
		elsif($op eq 'print'){ push @out, ($v{$n}//0); return @out if @out > 50 }
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
	my @out = @_;
	my $f = 0;
	$f += 1 if @out > 0;
	for my $i (0..$#TARGET){
		if($i < @out){
			my $d = abs($out[$i] - $TARGET[$i]);
			$f += $d==0 ? 10 : 10/(1+$d);
		}
	}
	$f -= (@out - @TARGET)*0.5 if @out > @TARGET;
	return $f;
}

# --- GA ops ---
sub rg { [map { int rand 256 } 1..$INIT_GLEN] }

sub mutate {
	my @g = @{$_[0]};
	# point mutations
	for(@g){ $_ = int rand 256 if rand() < $MRATE }
	# grow: insert a random instruction
	if(rand() < $GROW && @g < $MAX_GLEN){
		my $pos = 2 * int(rand(@g/2 + 1));
		splice @g, $pos, 0, int(rand(256)), int(rand(256));
	}
	# shrink: delete a random instruction
	if(rand() < $GROW && @g > 4){
		my $pos = 2 * int(rand(@g/2));
		splice @g, $pos, 2;
	}
	return \@g;
}

sub cross {
	my ($a,$b) = @_;
	# pick a cut point in each parent (at instruction boundaries)
	my $pa = 2*int(rand(@$a/2)); $pa = 2 if $pa == 0;
	my $pb = 2*int(rand(@$b/2)); $pb = 2 if $pb == 0;
	my @child = (@{$a}[0..$pa-1], @{$b}[$pb..$#$b]);
	# cap length
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
my $best_f = -1;
my $best_g;

my $target_str = join(', ',@TARGET);
my $max_fit = @TARGET * 10 + 1;
print "target: [$target_str]\n";
print "pop=$POP gens=$GENS (genomes can grow up to $MAX_GLEN bytes)\n\n";

for my $gen (1..$GENS){
	my @fit;
	for my $g (@pop){
		my @ins = decode($g);
		my @out = run(@ins);
		push @fit, fitness(@out);
	}

	# track best
	my $bi = 0;
	for(1..$#fit){ $bi=$_ if $fit[$_]>$fit[$bi] }
	if($fit[$bi] > $best_f){
		$best_f = $fit[$bi];
		$best_g = [@{$pop[$bi]}];
		my @ins = decode($best_g);
		my @out = run(@ins);
		my $os = @out ? join(",",@out) : "-";
		my $nb = scalar @{$best_g};
		printf "gen %4d  fit=%6.2f  len=%2db  out=[%s]\n", $gen, $best_f, $nb, $os;
	}
	elsif($gen % 100 == 0){
		my $avg = 0; $avg += $_ for @fit; $avg /= @fit;
		my $avg_len = 0; $avg_len += scalar @$_ for @pop; $avg_len /= @pop;
		printf "gen %4d  best=%6.2f  avg=%5.2f  avg_len=%.0fb\n", $gen, $best_f, $avg, $avg_len;
	}

	# perfect?
	last if $best_f >= $max_fit;

	# next gen
	my @si = sort { $fit[$b] <=> $fit[$a] } 0..$#pop;
	my @next;
	push @next, [@{$pop[$si[$_]]}] for 0..$ELITE-1;
	while(@next < $POP){
		my $a = tourney(\@pop,\@fit);
		my $b = tourney(\@pop,\@fit);
		push @next, mutate(cross($pop[$a],$pop[$b]));
	}
	@pop = @next;
}

# results
print "\n" . "="x50 . "\n";
my @ins = decode($best_g);
my @out = run(@ins);
print "best program (fitness $best_f, ".scalar(@{$best_g})." bytes, ".scalar(@ins)." instructions):\n\n";
for(@ins){ print "  $_->[0] $_->[1]\n" }
print "\noutput: [" . join(", ",@out) . "]\n";
print "target: [" . join(", ",@TARGET) . "]\n";
