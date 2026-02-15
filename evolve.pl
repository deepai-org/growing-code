#!/usr/bin/perl
# evolve.pl - the missing piece: evolve toten programs
# usage: perl evolve.pl [generations] [target_max]
#   default: 500 generations, target 1..10

use strict;
use warnings;

my $GENS = $ARGV[0] || 500;
my $TMAX = $ARGV[1] || 10;
my @TARGET = (1..$TMAX);

my $POP = 100;
my $GLEN = 24;       # 12 instructions
my $MRATE = 0.08;
my $ELITE = 5;
my $TSTEPS = 10000;  # max interpreter steps

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
sub rg { [map { int rand 256 } 1..$GLEN] }

sub mutate {
	my @g = @{$_[0]};
	for(@g){ $_ = int rand 256 if rand() < $MRATE }
	return \@g;
}

sub cross {
	my ($a,$b) = @_;
	my $p = 2*int(rand($GLEN/2));
	$p = 2 if $p == 0;
	return [map { $_ < $p ? $a->[$_] : $b->[$_] } 0..$GLEN-1];
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

print "target: [@{[join ', ',@TARGET]}]\n";
print "pop=$POP genome=${GLEN}b gens=$GENS\n\n";

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
		printf "gen %4d  fit=%6.2f  out=[%s]\n", $gen, $best_f, $os;
	}
	elsif($gen % 100 == 0){
		my $avg = 0; $avg += $_ for @fit; $avg /= @fit;
		printf "gen %4d  best=%6.2f  avg=%5.2f\n", $gen, $best_f, $avg;
	}

	# perfect?
	last if $best_f >= @TARGET * 10;

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
print "best program (fitness $best_f):\n\n";
for(@ins){ print "  $_->[0] $_->[1]\n" }
print "\noutput: [" . join(", ",@out) . "]\n";
print "target: [" . join(", ",@TARGET) . "]\n";
