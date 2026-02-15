#!/usr/bin/perl
# landscape.pl - Fitness landscape analyzer
#
# Takes a .tot program and a target, applies every possible single-instruction
# mutation, and maps the fitness landscape around that program.
#
# Usage: perl landscape.pl <file.tot> <target>
# Example: perl landscape.pl examples/evolved-squares.tot squares
#
# Shows: how many mutations improve, degrade, or are neutral.
# If 99.9% degrade, the program is trapped in a local optimum.
# If neutral paths exist, more evolution time could help.

use strict;
use warnings;
use List::Util qw(min max);

my $file = $ARGV[0] or die "usage: perl landscape.pl <file.tot> <target>\n";
my $targ_name = $ARGV[1] or die "usage: perl landscape.pl <file.tot> <target>\n";

my $MAX_STEPS = 5000;

# === TARGET SETUP ===
my %generators = (
	count   => sub { 1 .. $_[0] },
	squares => sub { map { $_*$_ } 1 .. $_[0] },
	fib     => sub { my $n=shift; my @f=(1,1); push @f, $f[-1]+$f[-2] while @f<$n; @f },
	primes  => sub {
		my $n=shift; my @p; my $c=2;
		while(@p<$n){
			my $ok=1; for(2..sqrt($c)){if($c%$_==0){$ok=0;last}}
			push @p,$c if $ok; $c++;
		} @p
	},
	evens   => sub { map { $_*2 } 1..$_[0] },
	odds    => sub { map { $_*2-1 } 1..$_[0] },
	powers  => sub { map { 2**($_-1) } 1..$_[0] },
);

die "Unknown target '$targ_name'\n" unless $generators{$targ_name};

my $N = { count=>12, squares=>12, fib=>9, primes=>9, evens=>12, odds=>12, powers=>12 }->{$targ_name};
my @TARGET = $generators{$targ_name}->($N);

# === LOAD PROGRAM ===
open my $fh, '<', $file or die "can't open $file: $!\n";
my @program;
while (<$fh>) {
	chomp; s/#.*//; s/^\s+|\s+$//g;
	next unless /\S/;
	my ($op, $n) = split /\s+/;
	push @program, [$op, $n // 0];
}
close $fh;

die "no instructions in $file\n" unless @program;

# === ALL OPCODES ===
my @ALL_OPS = qw(mark inc add sub mul div mod zero setv setc swap print if ifnot up down stop);

# === VM (same as grow_v3) ===
sub run_program {
	my ($genome, $limit_out) = @_;
	my @ins = @$genome;
	my %reg;
	my $acc = 0;
	my $pc = 0;
	my @out;
	my $steps = 0;

	while ($pc >= 0 && $pc < @ins && $steps++ < $MAX_STEPS) {
		my ($op, $arg) = @{$ins[$pc]};

		if    ($op eq 'mark') { $acc = $arg }
		elsif ($op eq 'inc')  { $reg{$arg} = ($reg{$arg}//0) + 1 }
		elsif ($op eq 'add')  { $reg{$acc} = ($reg{$acc}//0) + ($reg{$arg}//0) }
		elsif ($op eq 'sub')  { $reg{$acc} = ($reg{$acc}//0) - ($reg{$arg}//0) }
		elsif ($op eq 'mul')  { $reg{$acc} = ($reg{$acc}//0) * ($reg{$arg}//0) }
		elsif ($op eq 'div')  { $reg{$acc} = int(($reg{$acc}//0) / ($reg{$arg}//1)) if ($reg{$arg}//0) != 0 }
		elsif ($op eq 'mod')  { $reg{$acc} = ($reg{$acc}//0) % $reg{$arg} if ($reg{$arg}//0) != 0 }
		elsif ($op eq 'zero') { $reg{$arg} = 0 }
		elsif ($op eq 'setv') { $reg{$acc} = ($reg{$arg}//0) }
		elsif ($op eq 'setc') { $reg{$acc} = $arg }
		elsif ($op eq 'swap') { my $t=($reg{$acc}//0); $reg{$acc}=($reg{$arg}//0); $reg{$arg}=$t }
		elsif ($op eq 'print'){
			push @out, ($reg{$arg}//0);
			return \@out if @out >= $limit_out;
		}
		elsif ($op eq 'if')   { $pc += 2 if ($reg{$arg}//0) == 0 }
		elsif ($op eq 'ifnot'){ $pc += 2 if ($reg{$arg}//0) != 0 }
		elsif ($op eq 'stop') { last }
		elsif ($op eq 'up' || $op eq 'down') {
			my $dir = ($op eq 'up') ? -1 : 1;
			my $scan = $pc;
			my $found = 0;
			while (1) {
				$scan += $dir;
				last if $scan < 0 || $scan >= @ins;
				if ($ins[$scan][0] eq 'mark' && $ins[$scan][1] == $arg) {
					$pc = $scan;
					$found = 1;
					last;
				}
			}
			next if $found;
		}
		$pc++;
	}
	return \@out;
}

# === FITNESS (streak + relative error, same as grow_v3) ===
sub calc_fitness {
	my @out = @{$_[0]};
	return 0 if @out == 0;

	my $score = 0;
	my $len = min(scalar @out, scalar @TARGET);

	my $streak = 0;
	for (0..$len-1) { last if $out[$_] != $TARGET[$_]; $streak++ }
	$score += ($streak * $streak) * 10;

	for (0..$len-1) {
		my $diff = abs($out[$_] - $TARGET[$_]);
		if ($diff == 0) { $score += 20 }
		else {
			my $div = max(1, abs($TARGET[$_]));
			$score += 20 / (1 + ($diff/$div) * 10);
		}
	}

	$score -= abs(scalar(@out) - scalar(@TARGET)) * 5;
	return $score;
}

# === BASELINE ===
my $base_out = run_program(\@program, scalar(@TARGET) + 5);
my $base_fit = calc_fitness($base_out);
my $base_match = 0;
for (0..$#TARGET) { last if $_ >= @$base_out || $base_out->[$_] != $TARGET[$_]; $base_match++ }

print "=" x 60 . "\n";
print "Fitness Landscape Analysis\n";
print "=" x 60 . "\n";
printf "Program:  %s (%d instructions)\n", $file, scalar @program;
printf "Target:   %s [%s]\n", $targ_name, join(',', @TARGET);
printf "Output:   [%s]\n", join(',', @$base_out);
printf "Baseline: fitness=%.2f  matched=%d/%d\n\n", $base_fit, $base_match, scalar @TARGET;

# === ENUMERATE ALL SINGLE MUTATIONS ===
my @results;   # { type, position, detail, fitness, delta }

for my $pos (0..$#program) {
	my ($orig_op, $orig_arg) = @{$program[$pos]};

	# 1. Change opcode (keep operand)
	for my $new_op (@ALL_OPS) {
		next if $new_op eq $orig_op;
		my @mut = map { [$_->[0], $_->[1]] } @program;
		$mut[$pos] = [$new_op, $orig_arg];
		my $out = run_program(\@mut, scalar(@TARGET) + 5);
		my $fit = calc_fitness($out);
		push @results, {
			type => 'opcode', pos => $pos,
			detail => "$orig_op->$new_op",
			fitness => $fit, delta => $fit - $base_fit,
		};
	}

	# 2. Change operand (keep opcode)
	for my $new_arg (0..9) {
		next if $new_arg == $orig_arg;
		my @mut = map { [$_->[0], $_->[1]] } @program;
		$mut[$pos] = [$orig_op, $new_arg];
		my $out = run_program(\@mut, scalar(@TARGET) + 5);
		my $fit = calc_fitness($out);
		push @results, {
			type => 'operand', pos => $pos,
			detail => "$orig_arg->$new_arg",
			fitness => $fit, delta => $fit - $base_fit,
		};
	}

	# 3. Delete instruction
	if (@program > 2) {
		my @mut = map { [$_->[0], $_->[1]] } @program;
		splice @mut, $pos, 1;
		my $out = run_program(\@mut, scalar(@TARGET) + 5);
		my $fit = calc_fitness($out);
		push @results, {
			type => 'delete', pos => $pos,
			detail => "delete $orig_op $orig_arg",
			fitness => $fit, delta => $fit - $base_fit,
		};
	}
}

# 4. Swap each pair of instructions
for my $i (0..$#program) {
	for my $j ($i+1..$#program) {
		my @mut = map { [$_->[0], $_->[1]] } @program;
		($mut[$i], $mut[$j]) = ($mut[$j], $mut[$i]);
		my $out = run_program(\@mut, scalar(@TARGET) + 5);
		my $fit = calc_fitness($out);
		push @results, {
			type => 'swap', pos => $i,
			detail => "swap $i<->$j",
			fitness => $fit, delta => $fit - $base_fit,
		};
	}
}

# === ANALYSIS ===
my ($improved, $neutral, $degraded, $lethal) = (0, 0, 0, 0);
my $threshold = max(1, $base_fit * 0.01);  # 1% tolerance for "neutral"

for my $r (@results) {
	if ($r->{delta} > $threshold) { $improved++ }
	elsif ($r->{delta} >= -$threshold) { $neutral++ }
	elsif ($r->{fitness} <= 0) { $lethal++ }
	else { $degraded++ }
}

my $total = scalar @results;
printf "Mutations tested: %d\n\n", $total;

printf "  Improved:  %4d (%5.1f%%)  — better fitness\n", $improved, $improved/$total*100;
printf "  Neutral:   %4d (%5.1f%%)  — within 1%% of baseline\n", $neutral, $neutral/$total*100;
printf "  Degraded:  %4d (%5.1f%%)  — worse fitness\n", $degraded, $degraded/$total*100;
printf "  Lethal:    %4d (%5.1f%%)  — zero fitness (program dies)\n", $lethal, $lethal/$total*100;

# histogram of fitness deltas
print "\nFitness delta distribution:\n";
my @bins = (-999, -100, -50, -10, -1, 0, 1, 10, 50, 100, 999);
my @bin_labels = ('<-100', '-100..-50', '-50..-10', '-10..-1', '-1..0', '0..+1', '+1..+10', '+10..+50', '+50..+100', '>+100');
my @counts = (0) x scalar @bin_labels;
for my $r (@results) {
	for my $i (0..$#bin_labels) {
		if ($r->{delta} > $bins[$i] && $r->{delta} <= $bins[$i+1]) {
			$counts[$i]++;
			last;
		}
	}
}
my $max_count = max(1, @counts ? (sort {$b<=>$a} @counts)[0] : 1);
for my $i (0..$#bin_labels) {
	my $bar = '#' x int($counts[$i] / $max_count * 40);
	printf "  %10s |%-40s| %d\n", $bin_labels[$i], $bar, $counts[$i];
}

# top 5 improvements
print "\nTop 5 improving mutations:\n";
my @sorted = sort { $b->{delta} <=> $a->{delta} } @results;
for my $i (0..min(4, $#sorted)) {
	last if $sorted[$i]{delta} <= 0;
	printf "  +%.2f  [%d] %s (%s)\n",
		$sorted[$i]{delta}, $sorted[$i]{pos},
		$sorted[$i]{detail}, $sorted[$i]{type};
}

# top 5 neutral paths
print "\nTop 5 neutral mutations (within 1%%):\n";
my @neutrals = sort { abs($a->{delta}) <=> abs($b->{delta}) }
	grep { abs($_->{delta}) <= $threshold && $_->{delta} != 0 } @results;
for my $i (0..min(4, $#neutrals)) {
	printf "  %+.2f  [%d] %s (%s)\n",
		$neutrals[$i]{delta}, $neutrals[$i]{pos},
		$neutrals[$i]{detail}, $neutrals[$i]{type};
}

# diagnosis
print "\n" . "=" x 60 . "\n";
if ($improved == 0 && $neutral < $total * 0.02) {
	print "DIAGNOSIS: Deep local optimum. No improving mutations,\n";
	print "almost no neutral paths. The program is trapped.\n";
} elsif ($improved == 0 && $neutral > 0) {
	print "DIAGNOSIS: Local optimum with neutral ridges.\n";
	print "Neutral drift could reach a new gradient — more time may help.\n";
} elsif ($improved > 0 && $improved < $total * 0.01) {
	print "DIAGNOSIS: Narrow escape path. Very few improving mutations\n";
	print "exist — evolution needs luck or targeted search to find them.\n";
} elsif ($improved > 0) {
	printf "DIAGNOSIS: Active landscape. %d improving mutations available.\n", $improved;
	print "Evolution should continue to make progress.\n";
}
