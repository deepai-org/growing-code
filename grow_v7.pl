#!/usr/bin/perl
# grow_v7.pl - Lexicase + Structural Macro-Mutations
#
# Builds on grow_v6 (lexicase selection) and adds two new mutation types
# that give evolution "bigger Lego bricks" for building nested loops:
#
#   Loop Wrap (3%): Wraps a random block of existing instructions in
#     mark N ... up N, creating a loop skeleton in one step.
#     Evolution still has to wire the exit condition and register usage.
#
#   Mod-If Insert (3%): Injects a [mark A / setv B / mod C / if A]
#     pattern — the divisibility-check building block for trial division.
#     Evolution still has to place it correctly inside a loop.
#
# These bridge the structural gap that point mutations can't cross:
# single-loop → nested-loop requires 3-4 simultaneous mutations via
# point changes, but one macro-mutation can create the skeleton.
#
# Usage: perl grow_v7.pl [target] [generations] [seed]
# Example: perl grow_v7.pl primes 3000
#          perl grow_v7.pl fib 2000 42

use strict;
use warnings;
use List::Util qw(min max sum shuffle);

# === CONFIGURATION ===
my $targ_name = $ARGV[0] || 'count';
my $MAX_GENS  = $ARGV[1] || 2000;
my $SEED      = $ARGV[2];

srand($SEED) if defined $SEED;

my $POP_SIZE       = 200;
my $ELITE_SIZE     = 10;
my $MAX_LEN        = 64;
my $INIT_LEN       = 16;
my $MAX_STEPS      = 5000;
my $SOUP_COUNT     = 10000;
my $HGT_INTERVAL   = 10;
my $HGT_COUNT      = 5;
my $EXTINCT_THRESH  = 50;
my $CROSSOVER_RATE  = 0.50;

# Tribal config (primes only)
my $TRIBE_SIZE      = 50;
my $TRIBE_GENS      = 200;
my $TRIBE_ELITE     = 5;

# === INSTRUCTION SET (weighted for random generation) ===
my @OPS_WEIGHTED = (
	('mark')  x 4,
	('inc')   x 3,
	('add')   x 3,
	('print') x 3,
	('up')    x 3,
	('setv')  x 2,
	('if')    x 2,
	qw(sub mul div mod zero setc swap ifnot down stop)
);

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

die "Unknown target '$targ_name'\nTargets: ".join(', ', sort keys %generators)."\n"
	unless $generators{$targ_name};

my $N = { count=>12, squares=>12, fib=>9, primes=>9, evens=>12, odds=>12, powers=>12 }->{$targ_name};
my @EXTENDED = $generators{$targ_name}->($N + 5);
my @TARGET   = @EXTENDED[0..$N-1];

print "=" x 60 . "\n";
print "grow_v7.pl — Lexicase + Macro-Mutations\n";
print "=" x 60 . "\n";
print "Target:   $targ_name\n";
print "Training: [" . join(',', @TARGET) . "]\n";
print "Testing:  [" . join(',', @EXTENDED) . "]\n";
print "Seed:     " . (defined $SEED ? $SEED : "random") . "\n\n";

# === VIRTUAL MACHINE ===
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

# === RANDOM GENOME ===
sub random_genome {
	my @g;
	for (1..$INIT_LEN) {
		push @g, [$OPS_WEIGHTED[rand @OPS_WEIGHTED], int(rand(10))];
	}
	return \@g;
}

# === SEMANTIC MUTATION ===
sub mutate {
	my $genome = shift;
	my @g = map { [$_->[0], $_->[1]] } @$genome;

	my $r = rand();

	if ($r < 0.10) {
		return \@g if @g >= $MAX_LEN;
		my $pos = int(rand(@g+1));
		splice @g, $pos, 0, [$OPS_WEIGHTED[rand @OPS_WEIGHTED], int(rand(10))];
	}
	elsif ($r < 0.20) {
		return \@g if @g <= 2;
		splice @g, int(rand(@g)), 1;
	}
	elsif ($r < 0.50) {
		my $idx = int(rand(@g));
		if (rand() < 0.5) {
			$g[$idx][1] = ($g[$idx][1] + (rand()<.5?1:-1)) % 10;
		} else {
			$g[$idx][1] = int(rand(10));
		}
	}
	elsif ($r < 0.70) {
		my $idx = int(rand(@g));
		$g[$idx][0] = $OPS_WEIGHTED[rand @OPS_WEIGHTED];
	}
	elsif ($r < 0.85) {
		my $i = int(rand(@g));
		my $j = int(rand(@g));
		($g[$i], $g[$j]) = ($g[$j], $g[$i]);
	}
	elsif ($r < 0.92) {
		return \@g if @g >= $MAX_LEN - 3;
		my $len = 2 + int(rand(3));
		my $src = int(rand(max(1, scalar(@g) - $len)));
		my $dst = int(rand(@g));
		my @chunk = map { [$_->[0], $_->[1]] } @g[$src .. min($src+$len-1, $#g)];
		splice @g, $dst, 0, @chunk;
	}
	# --- MACRO-MUTATION: LOOP WRAP (3%) ---
	# Wraps a random block of existing instructions in mark N ... up N,
	# creating a loop skeleton. Evolution must add the exit condition.
	elsif ($r < 0.95) {
		return \@g if @g >= $MAX_LEN - 2 || @g < 3;
		my $mark_val = int(rand(10));
		my $block_start = int(rand(@g));
		my $block_len = min(2 + int(rand(5)), scalar(@g) - $block_start);
		# insert up AFTER the block, then mark BEFORE (order matters for indices)
		splice @g, $block_start + $block_len, 0, ['up', $mark_val];
		splice @g, $block_start, 0, ['mark', $mark_val];
	}
	# --- MACRO-MUTATION: MOD-IF INSERT (3%) ---
	# Injects [mark A / setv B / mod C / if A] — a divisibility check
	# building block. Evolution must place it inside a loop and wire
	# the right registers.
	elsif ($r < 0.98) {
		return \@g if @g >= $MAX_LEN - 4;
		my $pos = int(rand(@g + 1));
		my $result_reg = int(rand(10));
		my $source_reg = int(rand(10));
		$source_reg = ($result_reg + 1) % 10 if $source_reg == $result_reg;
		my $divisor_reg = int(rand(10));
		$divisor_reg = ($divisor_reg + 1) % 10 if $divisor_reg == $result_reg;
		splice @g, $pos, 0,
			['mark', $result_reg],
			['setv', $source_reg],
			['mod', $divisor_reg],
			['if', $result_reg];
	}

	splice @g, $MAX_LEN if @g > $MAX_LEN;
	return \@g;
}

# === BEHAVIORAL CLASSIFICATION ===
sub classify {
	my ($genome, $output) = @_;
	my @out = @$output;

	my $output_count = scalar @out;
	my %seen; $seen{$_}++ for @out;
	my $distinct = scalar keys %seen;

	my $increasing = (@out >= 2) ? 1 : 0;
	for (1..$#out) { if ($out[$_] <= $out[$_-1]) { $increasing = 0; last } }

	my $positive = 1;
	for (@out) { if ($_ <= 0) { $positive = 0; last } }

	my $loops = ($output_count > scalar(@$genome) / 2) ? 1 : 0;

	my $has_cond = 0;
	for (@$genome) { if ($_->[0] =~ /^(if|ifnot)$/) { $has_cond = 1; last } }

	my $skips = 0;
	if (@out >= 2 && $increasing) {
		for (1..$#out) { $skips++ if $out[$_] > $out[$_-1] + 1 }
	}

	my %regs;
	for (@$genome) { $regs{$_->[1]}++ }
	my $reg_count = scalar keys %regs;

	return {
		output_count => $output_count,
		distinct     => $distinct,
		increasing   => $increasing,
		positive     => $positive,
		loops        => $loops,
		has_cond     => $has_cond,
		skips        => $skips,
		reg_count    => $reg_count,
	};
}

# ============================================================
# PHASE 1: PRIMORDIAL SOUP
# ============================================================
sub generate_soup {
	print "=== PHASE 1: PRIMORDIAL SOUP ===\n";
	print "Generating $SOUP_COUNT random programs...\n";

	my %bins;

	for (1..$SOUP_COUNT) {
		my $genome = random_genome();
		my $output = run_program($genome, 30);
		my @out = @$output;

		next if @out == 0;

		my $feat = classify($genome, $output);

		my $key = join(',',
			min(4, int($feat->{output_count} / 3)),
			min(3, int($feat->{distinct} / 3)),
			$feat->{loops}       ? 1 : 0,
			$feat->{increasing}  ? 1 : 0,
			$feat->{has_cond}    ? 1 : 0,
			min(2, int($feat->{skips} / 2)),
		);

		my $score = $feat->{output_count} * 2
			+ $feat->{distinct} * 3
			+ ($feat->{increasing} ? 15 : 0)
			+ ($feat->{loops} ? 10 : 0)
			+ ($feat->{has_cond} ? 8 : 0)
			+ $feat->{skips} * 5
			+ $feat->{reg_count} * 2;

		if (!$bins{$key} || $score > $bins{$key}{score}) {
			$bins{$key} = {
				genome => $genome,
				output => $output,
				feat   => $feat,
				score  => $score,
			};
		}
	}

	my @soup = values %bins;

	my ($n_loops, $n_inc, $n_cond, $n_skip) = (0,0,0,0);
	for (@soup) {
		$n_loops++ if $_->{feat}{loops};
		$n_inc++   if $_->{feat}{increasing};
		$n_cond++  if $_->{feat}{has_cond};
		$n_skip++  if $_->{feat}{skips} > 0;
	}
	printf "Soup: %d fragments in %d behavioral niches\n", scalar @soup, scalar keys %bins;
	printf "  loops:%d  increasing:%d  conditional:%d  skipping:%d\n\n",
		$n_loops, $n_inc, $n_cond, $n_skip;

	return \@soup;
}

# ============================================================
# HORIZONTAL GENE TRANSFER
# ============================================================
sub inject_fragment {
	my ($genome, $fragment) = @_;
	my @g = map { [$_->[0], $_->[1]] } @$genome;
	my @f = @{$fragment->{genome}};

	my $flen = min(scalar @f, 2 + int(rand(5)));
	my $fsrc = int(rand(max(1, scalar(@f) - $flen)));
	my @chunk = map { [$_->[0], $_->[1]] } @f[$fsrc .. min($fsrc+$flen-1, $#f)];

	my $pos = int(rand(@g + 1));
	splice @g, $pos, 0, @chunk;

	splice @g, $MAX_LEN if @g > $MAX_LEN;

	return \@g;
}

# ============================================================
# HOMOLOGOUS CROSSOVER
# ============================================================
sub homologous_cross {
	my ($a, $b) = @_;

	my (%ma, %mb);
	for my $i (0..$#$a) { $ma{$a->[$i][1]} //= $i if $a->[$i][0] eq 'mark' }
	for my $i (0..$#$b) { $mb{$b->[$i][1]} //= $i if $b->[$i][0] eq 'mark' }

	my @shared = grep { exists $ma{$_} && exists $mb{$_} } 0..9;

	if (@shared) {
		my $mark_val = $shared[int(rand(@shared))];
		my $pos_a = $ma{$mark_val};
		my $pos_b = $mb{$mark_val};

		my @child = (
			(map { [$_->[0], $_->[1]] } @{$a}[0 .. $pos_a-1]),
			(map { [$_->[0], $_->[1]] } @{$b}[$pos_b .. $#$b]),
		);
		splice @child, $MAX_LEN if @child > $MAX_LEN;
		return \@child if @child >= 2;
	}

	my $pa = int(rand(max(1, scalar @$a)));
	my $pb = int(rand(max(1, scalar @$b)));
	my @child = (
		(map { [$_->[0], $_->[1]] } @{$a}[0 .. $pa]),
		(map { [$_->[0], $_->[1]] } @{$b}[$pb .. $#$b]),
	);
	splice @child, $MAX_LEN if @child > $MAX_LEN;
	return @child >= 2 ? \@child : [map { [$_->[0],$_->[1]] } @$a];
}

# ============================================================
# LEXICASE SELECTION
# ============================================================
# Instead of aggregating fitness into one number, lexicase selects
# parents case-by-case. This protects "specialists" — a program
# that gets one hard case right survives even if it's mediocre overall.

# Per-case error: how wrong is this program on test case i?
sub case_error {
	my ($out, $case_idx, $target_ref) = @_;
	# No output at this position = large error
	return 1e6 if $case_idx >= scalar @$out;
	return abs($out->[$case_idx] - $target_ref->[$case_idx]);
}

# Epsilon-lexicase: select one parent from the population
# Each call shuffles cases differently, so different specialists
# can win on different selection events.
sub lexicase_select {
	my ($scored_ref, $target_ref) = @_;
	my @candidates = @$scored_ref;
	my $num_cases = scalar @$target_ref;

	# Shuffle test case order — this is the key randomization
	my @cases = shuffle(0 .. $num_cases - 1);

	for my $case (@cases) {
		last if @candidates <= 1;

		# Find best (lowest) error on this case among candidates
		my $best_err = 1e18;
		for my $c (@candidates) {
			my $err = case_error($c->{out}, $case, $target_ref);
			$best_err = $err if $err < $best_err;
		}

		# Epsilon: within 1 absolute or 1% of target value
		# (whichever is larger) counts as "equally good"
		my $eps = max(1, abs($target_ref->[$case]) * 0.01);

		# Keep only candidates within epsilon of the best
		@candidates = grep {
			case_error($_->{out}, $case, $target_ref) <= $best_err + $eps
		} @candidates;
	}

	# Random from survivors
	return $candidates[int(rand(@candidates))];
}

# ============================================================
# AGGREGATE FITNESS (for tracking, stagnation, and elites only)
# ============================================================

sub aggregate_fitness {
	my ($out_ref, $target_ref) = @_;
	my @out = @$out_ref;
	my @tgt = @$target_ref;
	return 0 if @out == 0;

	my $score = 0;
	my $len = min(scalar @out, scalar @tgt);

	my $streak = 0;
	for (0..$len-1) { last if $out[$_] != $tgt[$_]; $streak++ }
	$score += ($streak * $streak) * 10;

	for (0..$len-1) {
		my $diff = abs($out[$_] - $tgt[$_]);
		if ($diff == 0) { $score += 20 }
		else {
			my $div = max(1, abs($tgt[$_]));
			$score += 20 / (1 + ($diff/$div) * 10);
		}
	}

	$score -= abs(scalar(@out) - scalar(@tgt)) * 5;
	return $score;
}

# ============================================================
# CURRICULUM FITNESS FUNCTIONS (for non-target stages)
# ============================================================

sub viability_fitness {
	my @out = @{$_[0]};
	return 0 if @out == 0;
	my %seen; $seen{$_}++ for @out;
	return scalar(@out) * 5 + scalar(keys %seen) * 10 + (@out >= 5 ? 50 : 0);
}

sub structure_fitness {
	my @out = @{$_[0]};
	return 0 if @out < 2;
	my $score = scalar(@out) * 3;
	my $inc_count = 0;
	for (1..$#out) {
		if ($out[$_] > $out[$_-1]) { $score += 10; $inc_count++ }
		$score += 5 if $out[$_] > 0;
	}
	$score += 20 if $inc_count == $#out;
	return $score;
}

# ============================================================
# TRIBE TARGET GENERATORS
# ============================================================

sub gen_no2s {
	my $n = shift;
	my @seq; my $c = 1;
	while (@seq < $n) { push @seq, $c if $c % 2 != 0; $c++ }
	return @seq;
}

sub gen_no3s {
	my $n = shift;
	my @seq; my $c = 1;
	while (@seq < $n) { push @seq, $c if $c % 3 != 0; $c++ }
	return @seq;
}

sub gen_no5s {
	my $n = shift;
	my @seq; my $c = 1;
	while (@seq < $n) { push @seq, $c if $c % 5 != 0; $c++ }
	return @seq;
}

my %TRIBE_DEFS = (
	A => { name => 'Counters',   gen => sub { 1 .. $_[0] } },
	B => { name => 'No-2s',      gen => \&gen_no2s },
	C => { name => 'No-3s',      gen => \&gen_no3s },
	D => { name => 'No-5s',      gen => \&gen_no5s },
);

# ============================================================
# CURRICULUM STAGE DEFINITIONS (non-primes targets)
# ============================================================
my %STAGES = (
	count   => [
		{ name => 'viability', fn => \&viability_fitness, gens => 50 },
		{ name => 'target',    fn => undef },  # uses lexicase
	],
	evens   => [
		{ name => 'viability', fn => \&viability_fitness, gens => 50 },
		{ name => 'target',    fn => undef },
	],
	odds    => [
		{ name => 'viability', fn => \&viability_fitness, gens => 50 },
		{ name => 'target',    fn => undef },
	],
	powers  => [
		{ name => 'viability', fn => \&viability_fitness, gens => 50 },
		{ name => 'target',    fn => undef },
	],
	squares => [
		{ name => 'viability', fn => \&viability_fitness, gens => 50 },
		{ name => 'structure', fn => \&structure_fitness, gens => 100 },
		{ name => 'target',    fn => undef },
	],
	fib     => [
		{ name => 'viability', fn => \&viability_fitness, gens => 50 },
		{ name => 'structure', fn => \&structure_fitness, gens => 100 },
		{ name => 'target',    fn => undef },
	],
);

# ============================================================
# EVOLVE A SINGLE TRIBE (with lexicase selection)
# ============================================================
sub evolve_tribe {
	my ($tribe_name, $tribe_def, $soup, $gens) = @_;
	my @tribe_target = $tribe_def->{gen}->(12);

	printf "  Tribe %s (%s): target=[%s]\n",
		$tribe_name, $tribe_def->{name}, join(',', @tribe_target[0..min(9,$#tribe_target)]);

	my @pop;
	if (@$soup >= $TRIBE_SIZE) {
		my @shuffled = shuffle @$soup;
		@pop = map { [ map { [$_->[0],$_->[1]] } @{$_->{genome}} ] } @shuffled[0..$TRIBE_SIZE-1];
	} else {
		push @pop, [ map { [$_->[0],$_->[1]] } @{$_->{genome}} ] for @$soup;
		while (@pop < $TRIBE_SIZE) { push @pop, random_genome() }
	}

	my $stagnation = 0;
	my $tribe_best_score = -1;
	my $tribe_best_out;

	for my $g (1..$gens) {
		my @scored;

		for my $genome (@pop) {
			my $out = run_program($genome, scalar(@tribe_target) + 5);
			my $fit = aggregate_fitness($out, \@tribe_target);
			push @scored, { genome => $genome, fitness => $fit, out => $out };
		}

		# Sort by aggregate for elite tracking
		@scored = sort { $b->{fitness} <=> $a->{fitness} } @scored;

		if ($scored[0]{fitness} > $tribe_best_score) {
			$tribe_best_score = $scored[0]{fitness};
			$tribe_best_out = $scored[0]{out};
			$stagnation = 0;
		} else {
			$stagnation++;
		}

		if ($g % 50 == 0 || $g == $gens) {
			my @sample = @{$scored[0]{out}};
			@sample = @sample[0..min(7,$#sample)] if @sample > 8;
			printf "    [%s] gen %d: best=%.1f  out=[%s]\n",
				$tribe_def->{name}, $g, $tribe_best_score, join(',', @sample);
		}

		last if $stagnation > 40;

		if ($stagnation > 25) {
			$stagnation = 0;
			my @keep = map { $scored[$_]{genome} } 0..$TRIBE_ELITE-1;
			@pop = @keep;
			while (@pop < $TRIBE_SIZE) { push @pop, random_genome() }
			next;
		}

		# Lexicase selection for tribes too
		my @next;
		push @next, $scored[$_]{genome} for 0..$TRIBE_ELITE-1;
		while (@next < $TRIBE_SIZE) {
			if (rand() < 0.30) {
				my $p1 = lexicase_select(\@scored, \@tribe_target);
				my $p2 = lexicase_select(\@scored, \@tribe_target);
				push @next, mutate(homologous_cross($p1->{genome}, $p2->{genome}));
			} else {
				my $parent = lexicase_select(\@scored, \@tribe_target);
				push @next, mutate($parent->{genome});
			}
		}
		@pop = @next;
	}

	my $streak = 0;
	my @best_o = @{$tribe_best_out // []};
	for (0..min($#tribe_target, $#best_o)) {
		last if $best_o[$_] != $tribe_target[$_]; $streak++;
	}
	printf "    [%s] final: score=%.1f  streak=%d/%d\n\n",
		$tribe_def->{name}, $tribe_best_score, $streak, scalar @tribe_target;

	my @final_scored;
	for my $genome (@pop) {
		my $out = run_program($genome, scalar(@tribe_target) + 5);
		my $fit = aggregate_fitness($out, \@tribe_target);
		push @final_scored, { genome => $genome, fitness => $fit, out => $out };
	}
	@final_scored = sort { $b->{fitness} <=> $a->{fitness} } @final_scored;

	return \@final_scored;
}

# ============================================================
# LEXICASE EVOLUTION LOOP (target stage)
# ============================================================
# Runs one generation with lexicase selection. Used by both the
# primes merger phase and the standard target stage.
sub lexicase_generation {
	my ($pop_ref, $target_ref, $soup, $tribe_results, $gen, $state) = @_;
	my @pop = @$pop_ref;
	my @tgt = @$target_ref;

	my @scored;
	for my $genome (@pop) {
		my $out = run_program($genome, scalar(@tgt) + 5);
		my $fit = aggregate_fitness($out, \@tgt);
		push @scored, { genome => $genome, fitness => $fit, out => $out };
	}

	# Sort by aggregate for elite preservation and tracking
	@scored = sort { $b->{fitness} <=> $a->{fitness} } @scored;

	my $best = $scored[0];

	# Track best
	my $improved = 0;
	if ($best->{fitness} > $state->{stage_best}) {
		$state->{stage_best} = $best->{fitness};
		$state->{stagnation} = 0;
		$improved = 1;

		if ($best->{fitness} > $state->{best_ever_score}) {
			$state->{best_ever_score} = $best->{fitness};
			$state->{best_ever_genome} = [ map { [$_->[0],$_->[1]] } @{$best->{genome}} ];

			printf "Gen %d: Score %.1f  Out: [%s]\n",
				$gen, $best->{fitness}, join(',', @{$best->{out}});

			my $full = run_program($best->{genome}, scalar @EXTENDED);
			my @full_out = @$full;
			my $match = 0;
			for (0..$#EXTENDED) {
				last if $_ >= @full_out || $full_out[$_] != $EXTENDED[$_];
				$match++;
			}
			print "  Generalization: $match/" . scalar(@EXTENDED) . "\n";

			if ($match == scalar @EXTENDED) {
				print "\n*** PERFECT ALGORITHM DISCOVERED ***\n";
				print_code($best->{genome});
				print_summary($best->{genome}, $gen);
				exit 0;
			}
		}
	} else {
		$state->{stagnation}++;
	}

	# Extinction event
	if ($state->{stagnation} > $EXTINCT_THRESH) {
		$state->{stagnation} = 0;
		my @keep = map { $scored[$_]{genome} } 0..$ELITE_SIZE-1;
		my @new_pop = @keep;
		while (@new_pop < $POP_SIZE) {
			my $r = rand();
			if ($tribe_results && $r < 0.25) {
				my @keys = keys %$tribe_results;
				my $tk = $keys[int(rand(@keys))];
				my @tp = @{$tribe_results->{$tk}};
				my $idx = int(rand(min(10, scalar @tp)));
				push @new_pop, [ map { [$_->[0],$_->[1]] } @{$tp[$idx]{genome}} ];
			} elsif ($soup && @$soup > 0 && $r < 0.45) {
				my $frag = $soup->[int(rand(@$soup))];
				push @new_pop, [ map { [$_->[0],$_->[1]] } @{$frag->{genome}} ];
			} else {
				push @new_pop, random_genome();
			}
		}
		printf "Gen %d: !! EXTINCTION EVENT !!\n", $gen;
		return \@new_pop;
	}

	# HGT from soup
	if ($soup && @$soup > 0 && $gen % $HGT_INTERVAL == 0) {
		for (1..$HGT_COUNT) {
			my $idx = $ELITE_SIZE + int(rand(@scored - $ELITE_SIZE));
			next if $idx >= @scored;
			my $frag = $soup->[int(rand(@$soup))];
			$scored[$idx]{genome} = inject_fragment($scored[$idx]{genome}, $frag);
		}
	}

	# Inter-tribal crossover (primes only)
	if ($tribe_results && $gen % 5 == 0) {
		for (1..3) {
			my @keys = keys %$tribe_results;
			my $tk = $keys[int(rand(@keys))];
			my @tp = @{$tribe_results->{$tk}};
			next unless @tp;
			my $tribal_genome = $tp[int(rand(min(5, scalar @tp)))]{genome};
			my $pop_idx = $ELITE_SIZE + int(rand(@scored - $ELITE_SIZE));
			next if $pop_idx >= @scored;
			$scored[$pop_idx]{genome} = homologous_cross(
				$scored[$pop_idx]{genome}, $tribal_genome
			);
		}
	}

	# LEXICASE SELECTION for parent picking
	my @next;
	push @next, $scored[$_]{genome} for 0..$ELITE_SIZE-1;
	while (@next < $POP_SIZE) {
		if (rand() < $CROSSOVER_RATE) {
			my $p1 = lexicase_select(\@scored, \@tgt);
			my $p2 = lexicase_select(\@scored, \@tgt);
			push @next, mutate(homologous_cross($p1->{genome}, $p2->{genome}));
		} else {
			my $parent = lexicase_select(\@scored, \@tgt);
			push @next, mutate($parent->{genome});
		}
	}

	return \@next;
}

# ============================================================
# CURRICULUM STAGE (non-target, uses aggregate fitness)
# ============================================================
sub run_curriculum_stage {
	my ($pop_ref, $stage, $gen_offset) = @_;
	my @pop = @$pop_ref;
	my $fitness_fn = $stage->{fn};
	my $stage_gens = $stage->{gens};

	printf "=== STAGE: %s (%d gens) ===\n", uc($stage->{name}), $stage_gens;

	my $stagnation = 0;
	my $stage_best = -1;

	for my $g (1..$stage_gens) {
		my $gen = $gen_offset + $g;
		my @scored;

		for my $genome (@pop) {
			my $out = run_program($genome, scalar(@TARGET) + 5);
			my $fit = $fitness_fn->($out);
			push @scored, { genome => $genome, fitness => $fit, out => $out };
		}

		@scored = sort { $b->{fitness} <=> $a->{fitness} } @scored;

		if ($scored[0]{fitness} > $stage_best) {
			$stage_best = $scored[0]{fitness};
			$stagnation = 0;
		} else {
			$stagnation++;
		}

		if ($g % 20 == 0) {
			my @s = @{$scored[0]{out}};
			@s = @s[0..min(7,$#s)] if @s > 8;
			printf "  [%s] gen %d: best=%.1f  sample=[%s]\n",
				$stage->{name}, $gen, $stage_best, join(',', @s);
		}

		last if $stagnation > 30;

		my @next;
		push @next, $scored[$_]{genome} for 0..$ELITE_SIZE-1;
		my $top = min(50, scalar @scored);
		while (@next < $POP_SIZE) {
			my $parent = $scored[int(rand($top))]{genome};
			push @next, mutate($parent);
		}
		@pop = @next;
	}

	printf "  [%s] complete. Best: %.1f\n\n", $stage->{name}, $stage_best;
	return \@pop;
}

# ============================================================
# MAIN
# ============================================================

# Phase 1: generate primordial soup
my $soup = generate_soup();

# Seed initial population from soup
my @pop;
if (@$soup >= $POP_SIZE) {
	my @shuffled = shuffle @$soup;
	@pop = map { [ map { [$_->[0],$_->[1]] } @{$_->{genome}} ] } @shuffled[0..$POP_SIZE-1];
} else {
	push @pop, [ map { [$_->[0],$_->[1]] } @{$_->{genome}} ] for @$soup;
	while (@pop < $POP_SIZE) { push @pop, random_genome() }
}

if ($targ_name eq 'primes') {
	# ============================================================
	# PRIMES: TRIBAL + LEXICASE PATH
	# ============================================================

	# Viability stage
	my $pop_ref = run_curriculum_stage(\@pop, { name => 'viability', fn => \&viability_fitness, gens => 100 }, 0);

	# Tribal evolution
	print "=== TRIBAL EVOLUTION ($TRIBE_GENS gens each) ===\n";
	print "Splitting into 4 specialized tribes (with lexicase)...\n\n";

	my %tribe_results;
	for my $key (sort keys %TRIBE_DEFS) {
		$tribe_results{$key} = evolve_tribe($key, $TRIBE_DEFS{$key}, $soup, $TRIBE_GENS);
	}

	# Merger
	print "=== THE MERGER ===\n";
	my $per_tribe = int($POP_SIZE / 4);
	my @merged;
	for my $key (sort keys %tribe_results) {
		my @tribe_pop = @{$tribe_results{$key}};
		my $take = min($per_tribe, scalar @tribe_pop);
		for my $i (0..$take-1) {
			push @merged, [ map { [$_->[0],$_->[1]] } @{$tribe_pop[$i]{genome}} ];
		}
		printf "  Tribe %s: contributed %d genomes\n", $key, $take;
	}
	while (@merged < $POP_SIZE) {
		if (@$soup > 0 && rand() < 0.3) {
			my $frag = $soup->[int(rand(@$soup))];
			push @merged, [ map { [$_->[0],$_->[1]] } @{$frag->{genome}} ];
		} else {
			push @merged, random_genome();
		}
	}
	printf "  Total merged: %d\n\n", scalar @merged;

	# Directed evolution with LEXICASE SELECTION
	my $merger_gens = $MAX_GENS - 100 - $TRIBE_GENS;
	$merger_gens = max(100, $merger_gens);
	printf "=== LEXICASE PRIMES EVOLUTION (%d gens) ===\n", $merger_gens;
	printf "Selection: epsilon-lexicase on %d test cases\n", scalar @TARGET;
	printf "Crossover: %.0f%%  HGT: every %d gens\n\n", $CROSSOVER_RATE*100, $HGT_INTERVAL;

	my $state = {
		best_ever_score => -1,
		best_ever_genome => undef,
		stage_best => -1,
		stagnation => 0,
	};

	my $pop_ref2 = \@merged;
	for my $g (1..$merger_gens) {
		my $gen = 100 + $TRIBE_GENS + $g;
		$pop_ref2 = lexicase_generation($pop_ref2, \@TARGET, $soup, \%tribe_results, $gen, $state);
	}

	# Final report
	print "\n" . "=" x 60 . "\n";
	if ($state->{best_ever_genome}) {
		print_code($state->{best_ever_genome});
		print_summary($state->{best_ever_genome}, 100 + $TRIBE_GENS + $merger_gens);
	} else {
		print "No solution found.\n";
		my $best_fit = -1;
		my $best_g;
		for my $genome (@$pop_ref2) {
			my $out = run_program($genome, scalar(@TARGET) + 5);
			my $fit = aggregate_fitness($out, \@TARGET);
			if ($fit > $best_fit) { $best_fit = $fit; $best_g = $genome }
		}
		if ($best_g) {
			print "Best effort (score $best_fit):\n";
			print_code($best_g);
			print_summary($best_g, 100 + $TRIBE_GENS + $merger_gens);
		}
	}

} else {
	# ============================================================
	# NON-PRIMES: CURRICULUM + LEXICASE TARGET
	# ============================================================

	my @stages = @{$STAGES{$targ_name}};
	my $gen_offset = 0;
	my $pop_ref = \@pop;

	# Run curriculum stages (non-target stages use aggregate fitness)
	for my $stage_idx (0..$#stages) {
		my $stage = $stages[$stage_idx];
		my $is_final = ($stage_idx == $#stages);

		if (!$is_final) {
			$pop_ref = run_curriculum_stage($pop_ref, $stage, $gen_offset);
			$gen_offset += $stage->{gens};
		} else {
			# Target stage: lexicase selection
			my $target_gens = $MAX_GENS - $gen_offset;
			printf "=== LEXICASE TARGET (%d gens) ===\n", $target_gens;
			printf "Selection: epsilon-lexicase on %d test cases\n\n", scalar @TARGET;

			my $state = {
				best_ever_score => -1,
				best_ever_genome => undef,
				stage_best => -1,
				stagnation => 0,
			};

			for my $g (1..$target_gens) {
				my $gen = $gen_offset + $g;
				$pop_ref = lexicase_generation($pop_ref, \@TARGET, $soup, undef, $gen, $state);
			}

			# Final report
			print "\n" . "=" x 60 . "\n";
			if ($state->{best_ever_genome}) {
				print_code($state->{best_ever_genome});
				print_summary($state->{best_ever_genome}, $gen_offset + $target_gens);
			} else {
				print "No solution found.\n";
				my $best_fit = -1;
				my $best_g;
				for my $genome (@$pop_ref) {
					my $out = run_program($genome, scalar(@TARGET) + 5);
					my $fit = aggregate_fitness($out, \@TARGET);
					if ($fit > $best_fit) { $best_fit = $fit; $best_g = $genome }
				}
				if ($best_g) {
					print "Best effort (score $best_fit):\n";
					print_code($best_g);
					print_summary($best_g, $gen_offset + $target_gens);
				}
			}
			last;
		}
	}
}

# === OUTPUT HELPERS ===
sub print_code {
	my $g = shift;
	print "Program:\n";
	for my $i (0..$#$g) {
		printf "  %2d  %s %d\n", $i, $g->[$i][0], $g->[$i][1];
	}
}

sub print_summary {
	my ($genome, $gen) = @_;
	my $full = run_program($genome, scalar @EXTENDED + 10);
	my @full_out = @$full;
	my $match = 0;
	for (0..$#EXTENDED) {
		last if $_ >= @full_out || $full_out[$_] != $EXTENDED[$_];
		$match++;
	}
	print "\nOutput:   [" . join(',', @full_out) . "]\n";
	print "Expected: [" . join(',', @EXTENDED) . "]\n";
	printf "Matched:  %d/%d", $match, scalar @EXTENDED;
	print " -- GENERALIZED!" if $match > $N;
	print " -- PERFECT ALGORITHM!" if $match == scalar @EXTENDED;
	print "\n";
}
