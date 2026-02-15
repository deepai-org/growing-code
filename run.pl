#!/usr/bin/perl
# run.pl - standalone toten interpreter
#
# usage: perl run.pl <file.tot> [max_steps] [max_output]
#   default: 10000 steps, 100 output values
#
# reads toten source (opcode operand pairs, one per line)
# and executes it directly — no compilation needed.

use strict;
use warnings;

my $file = $ARGV[0] or die "usage: perl run.pl <file.tot> [max_steps] [max_output]\n";
my $TSTEPS = $ARGV[1] || 10000;
my $MAXOUT = $ARGV[2] || 100;

open my $fh, '<', $file or die "can't open $file: $!\n";
my @ins;
while(<$fh>){
	chomp;
	s/#.*//;        # strip comments
	s/^\s+|\s+$//g; # trim
	next unless /\S/;
	my ($op, $n) = split /\s+/;
	push @ins, [$op, $n // 0];
}
close $fh;

die "no instructions in $file\n" unless @ins;

# interpreter — same semantics as evolve.pl and toc.pl
my %v;
my $acc = 0;
my $pc = 0;
my $steps = 0;
my $printed = 0;

while($pc >= 0 && $pc <= $#ins && $steps < $TSTEPS){
	$steps++;
	my ($op, $n) = @{$ins[$pc]};

	if   ($op eq 'stop') { last }
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
	elsif($op eq 'swap') { my $tmp=$v{$acc}//0; $v{$acc}=$v{$n}//0; $v{$n}=$tmp }
	elsif($op eq 'print'){ print(($v{$n}//0)."\n"); $printed++; last if $printed >= $MAXOUT }
	elsif($op eq 'if')   { if(($v{$n}//0)==0){ $pc+=2; next } }
	elsif($op eq 'ifnot'){ if(($v{$n}//0)!=0){ $pc+=2; next } }
	elsif($op eq 'up'){
		my $s=$pc; my $r=$n;
		if($r==0){ $pc++; next }
		while($r>0){ $s--; last if $s<0; $r-- if $ins[$s][0] eq 'mark' }
		if($r==0){ $pc=$s; next }
	}
	elsif($op eq 'down'){
		my $s=$pc; my $r=$n;
		if($r==0){ $pc++; next }
		while($r>0){ $s++; last if $s>$#ins; $r-- if $ins[$s][0] eq 'mark' }
		if($r==0){ $pc=$s; next }
	}
	$pc++;
}
