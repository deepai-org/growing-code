#!/usr/bin/perl
# minimize.pl - strip dead/vestigial instructions from toten programs
#
# usage: perl minimize.pl <file.tot> [max_steps] [max_output]
#
# iteratively tries removing each instruction. if the output
# doesn't change, the instruction was dead weight. repeats
# until no more can be removed.

use strict;
use warnings;

my $file = $ARGV[0] or die "usage: perl minimize.pl <file.tot> [max_steps] [max_output]\n";
my $TSTEPS = $ARGV[1] || 10000;
my $MAXOUT = $ARGV[2] || 100;

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

sub run_prog {
	my @ins = @{$_[0]};
	return [] unless @ins;
	my %v;
	my $acc = 0;
	my $pc = 0;
	my @out;
	my $steps = 0;
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
		elsif($op eq 'print'){ push @out, ($v{$n}//0); return \@out if @out >= $MAXOUT }
		elsif($op eq 'if')   { if(($v{$n}//0)==0){ $pc+=2; next } }
		elsif($op eq 'ifnot'){ if(($v{$n}//0)!=0){ $pc+=2; next } }
		elsif($op eq 'up'){
			my $s=$pc; my $r=$n;
			if($r==0){$pc++; next}
			while($r>0){ $s--; last if $s<0; $r-- if $ins[$s][0] eq 'mark' }
			if($r==0){ $pc=$s; next }
		}
		elsif($op eq 'down'){
			my $s=$pc; my $r=$n;
			if($r==0){$pc++; next}
			while($r>0){ $s++; last if $s>$#ins; $r-- if $ins[$s][0] eq 'mark' }
			if($r==0){ $pc=$s; next }
		}
		$pc++;
	}
	return \@out;
}

my $orig = scalar @ins;
my $baseline = run_prog(\@ins);
my $baseline_str = join(',', @$baseline);

print "original: $orig instructions, " . scalar(@$baseline) . " output values\n";

# iteratively remove dead instructions
my $pass = 0;
my $changed = 1;
while($changed){
	$changed = 0;
	$pass++;
	my $i = 0;
	while($i < @ins){
		my @try = @ins;
		splice @try, $i, 1;
		my $out = run_prog(\@try);
		my $out_str = join(',', @$out);
		if($out_str eq $baseline_str){
			@ins = @try;
			$changed = 1;
			# don't advance $i — next instruction slid into this slot
		} else {
			$i++;
		}
	}
	printf "  pass %d: %d instructions\n", $pass, scalar @ins if $pass > 0;
}

my $removed = $orig - scalar @ins;
print "\nminimized: $orig -> " . scalar(@ins) . " instructions ($removed removed)\n\n";
for(@ins){ print "$_->[0] $_->[1]\n" }
