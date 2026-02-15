#!/usr/bin/perl
# trace.pl - step through a toten program showing execution state
#
# usage: perl trace.pl <file.tot> [max_steps] [max_output]
#
# shows each instruction as it executes, with the current
# variable state and accumulator pointer. great for understanding
# how evolved programs actually work.

use strict;
use warnings;

my $file = $ARGV[0] or die "usage: perl trace.pl <file.tot> [max_steps] [max_output]\n";
my $TSTEPS = $ARGV[1] || 200;
my $MAXOUT = $ARGV[2] || 50;

open my $fh, '<', $file or die "can't open $file: $!\n";
my @ins;
while(<$fh>){
	chomp;
	s/#.*//;
	s/^\s+|\s+$//g;
	next unless /\S/;
	my ($op, $n) = split /\s+/;
	push @ins, [$op, $n // 0];
}
close $fh;
die "no instructions in $file\n" unless @ins;

# print the source listing first
print "--- program listing ---\n";
for my $i (0..$#ins){
	printf "  %3d: %s %s\n", $i, $ins[$i][0], $ins[$i][1];
}
print "\n--- execution trace ---\n";
printf "%-6s %-12s  %-8s  %-30s  %s\n", "step", "instruction", "acc->", "vars", "output";
print "-" x 80 . "\n";

my %v;
my $acc = 0;
my $pc = 0;
my $steps = 0;
my @out;

sub vars_str {
	my @keys = sort { $a <=> $b } keys %v;
	return '-' unless @keys;
	return join(' ', map { "v$_=" . ($v{$_}//0) } @keys);
}

while($pc >= 0 && $pc <= $#ins && $steps < $TSTEPS){
	$steps++;
	my ($op, $n) = @{$ins[$pc]};
	my $istr = sprintf "%s %s", $op, $n;
	my $out_val = '';

	if   ($op eq 'stop') {
		printf "%4d   %-12s  acc->v%-3d %-30s  %s\n", $steps, $istr, $acc, vars_str(), "HALT";
		last;
	}
	elsif($op eq 'zero') { $v{$n}=0 }
	elsif($op eq 'mark') { $acc=$n }
	elsif($op eq 'setc') { $v{$acc}=$n }
	elsif($op eq 'setv') { $v{$acc}=$v{$n}//0 }
	elsif($op eq 'add')  { $v{$acc}=($v{$acc}//0)+($v{$n}//0) }
	elsif($op eq 'sub')  { $v{$acc}=($v{$acc}//0)-($v{$n}//0) }
	elsif($op eq 'mul')  { $v{$acc}=($v{$acc}//0)*($v{$n}//0) }
	elsif($op eq 'div')  { $v{$acc}=($v{$n}//0) ? int(($v{$acc}//0)/$v{$n}) : 0 }
	elsif($op eq 'mod')  { $v{$acc}=($v{$n}//0) ? ($v{$acc}//0)%$v{$n} : 0 }
	elsif($op eq 'inc')  { $v{$n}=($v{$n}//0)+1 }
	elsif($op eq 'dec')  { $v{$n}=($v{$n}//0)-1 }
	elsif($op eq 'print'){
		my $val = $v{$n}//0;
		push @out, $val;
		$out_val = "=> $val";
		if(@out >= $MAXOUT){
			printf "%4d   %-12s  acc->v%-3d %-30s  %s\n", $steps, $istr, $acc, vars_str(), $out_val;
			last;
		}
	}
	elsif($op eq 'if'){
		my $skip = (($v{$n}//0)==0);
		$out_val = $skip ? "(v$n==0, skip)" : "(v$n!=0, cont)";
		printf "%4d   %-12s  acc->v%-3d %-30s  %s\n", $steps, $istr, $acc, vars_str(), $out_val;
		if($skip){ $pc+=2; next }
		$pc++; next;
	}
	elsif($op eq 'ifnot'){
		my $skip = (($v{$n}//0)!=0);
		$out_val = $skip ? "(v$n!=0, skip)" : "(v$n==0, cont)";
		printf "%4d   %-12s  acc->v%-3d %-30s  %s\n", $steps, $istr, $acc, vars_str(), $out_val;
		if($skip){ $pc+=2; next }
		$pc++; next;
	}
	elsif($op eq 'up'){
		my $s=$pc; my $r=$n;
		if($r==0){
			$out_val = "(up 0, nop)";
			printf "%4d   %-12s  acc->v%-3d %-30s  %s\n", $steps, $istr, $acc, vars_str(), $out_val;
			$pc++; next;
		}
		while($r>0){ $s--; last if $s<0; $r-- if $ins[$s][0] eq 'mark' }
		if($r==0){
			$out_val = "-> line $s";
			printf "%4d   %-12s  acc->v%-3d %-30s  %s\n", $steps, $istr, $acc, vars_str(), $out_val;
			$pc=$s; next;
		}
		$out_val = "(no mark found)";
	}
	elsif($op eq 'down'){
		my $s=$pc; my $r=$n;
		if($r==0){
			$out_val = "(down 0, nop)";
			printf "%4d   %-12s  acc->v%-3d %-30s  %s\n", $steps, $istr, $acc, vars_str(), $out_val;
			$pc++; next;
		}
		while($r>0){ $s++; last if $s>$#ins; $r-- if $ins[$s][0] eq 'mark' }
		if($r==0){
			$out_val = "-> line $s";
			printf "%4d   %-12s  acc->v%-3d %-30s  %s\n", $steps, $istr, $acc, vars_str(), $out_val;
			$pc=$s; next;
		}
		$out_val = "(no mark found)";
	}

	printf "%4d   %-12s  acc->v%-3d %-30s  %s\n", $steps, $istr, $acc, vars_str(), $out_val;
	$pc++;
}

print "-" x 80 . "\n";
printf "%d steps, %d values output", $steps, scalar @out;
print ": [" . join(', ', @out) . "]" if @out;
print "\n";
