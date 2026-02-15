#!/usr/bin/perl
# grow_v4.pl - Fitness Sharing + Homologous Crossover
#
# Builds on grow_v3 (primordial soup + curriculum) and adds:
#   - Density-based fitness sharing: programs with similar outputs share
#     fitness, flattening local optima (the "static sieve" trap)
#   - Aggressive homologous crossover: swap functional blocks between
#     mark boundaries to teleport across the fitness landscape
#
# Usage: perl grow_v4.pl [target] [generations] [seed]
# Example: perl grow_v4.pl primes 3000
#          perl grow_v4.pl fib 2000 42

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
my $HGT_INTERVAL   = 10;    # inject soup fragments every N gens
my $HGT_COUNT      = 5;     # number of injections per interval
my $EXTINCT_THRESH  = 50;

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
print "grow_v3.pl — Primordial Soup Evolution\n";
print "=" x 60 . "\n";
print "Target:   $targ_name\n";
print "Training: [" . join(',', @TARGET) . "]\n";
print "Testing:  [" . join(',', @EXTENDED) . "]\n";
print "Seed:     " . (defined $SEED ? $SEED : "random") . "\n\n";

# === VIRTUAL MACHINE (identical to grow_v2) ===
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

# === SEMANTIC MUTATION (from grow_v2) ===
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
	elsif ($r < 0.95) {
		return \@g if @g >= $MAX_LEN - 3;
		my $len = 2 + int(rand(3));
		my $src = int(rand(max(1, scalar(@g) - $len)));
		my $dst = int(rand(@g));
		my @chunk = map { [$_->[0], $_->[1]] } @g[$src .. min($src+$len-1, $#g)];
		splice @g, $dst, 0, @chunk;
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

	# looping: many outputs from short program
	my $loops = ($output_count > scalar(@$genome) / 2) ? 1 : 0;

	# conditional usage
	my $has_cond = 0;
	for (@$genome) { if ($_->[0] =~ /^(if|ifnot)$/) { $has_cond = 1; last } }

	# gaps between consecutive outputs
	my $skips = 0;
	if (@out >= 2 && $increasing) {
		for (1..$#out) { $skips++ if $out[$_] > $out[$_-1] + 1 }
	}

	# distinct registers referenced
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

		# skip dead programs
		next if @out == 0;

		my $feat = classify($genome, $output);

		# MAP-Elites bin key: discretize behavioral features
		my $key = join(',',
			min(4, int($feat->{output_count} / 3)),
			min(3, int($feat->{distinct} / 3)),
			$feat->{loops}       ? 1 : 0,
			$feat->{increasing}  ? 1 : 0,
			$feat->{has_cond}    ? 1 : 0,
			min(2, int($feat->{skips} / 2)),
		);

		# interestingness score (behavioral richness, not target fitness)
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

	# report diversity
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

	# extract a random chunk (2-6 instructions) from the fragment
	my $flen = min(scalar @f, 2 + int(rand(5)));
	my $fsrc = int(rand(max(1, scalar(@f) - $flen)));
	my @chunk = map { [$_->[0], $_->[1]] } @f[$fsrc .. min($fsrc+$flen-1, $#f)];

	# insert at random position in genome
	my $pos = int(rand(@g + 1));
	splice @g, $pos, 0, @chunk;

	# trim if over max
	splice @g, $MAX_LEN if @g > $MAX_LEN;

	return \@g;
}

# ============================================================
# HOMOLOGOUS CROSSOVER
# ============================================================
# Structure-preserving crossover: align parents by shared mark
# instructions (functional boundaries), swap code between them.
# This lets a "loop body" from Parent A splice into the "control
# flow" of Parent B without destroying the logic inside either.
sub homologous_cross {
	my ($a, $b) = @_;

	# find mark positions in each parent (operand => first position)
	my (%ma, %mb);
	for my $i (0..$#$a) { $ma{$a->[$i][1]} //= $i if $a->[$i][0] eq 'mark' }
	for my $i (0..$#$b) { $mb{$b->[$i][1]} //= $i if $b->[$i][0] eq 'mark' }

	# find shared mark operands
	my @shared = grep { exists $ma{$_} && exists $mb{$_} } 0..9;

	if (@shared) {
		# pick a shared mark to cross at
		my $mark_val = $shared[int(rand(@shared))];
		my $pos_a = $ma{$mark_val};
		my $pos_b = $mb{$mark_val};

		# prefix from A (up to mark), suffix from B (from mark onward)
		my @child = (
			(map { [$_->[0], $_->[1]] } @{$a}[0 .. $pos_a-1]),
			(map { [$_->[0], $_->[1]] } @{$b}[$pos_b .. $#$b]),
		);
		splice @child, $MAX_LEN if @child > $MAX_LEN;
		return \@child if @child >= 2;
	}

	# fallback: simple one-point crossover
	my $pa = int(rand(max(1, scalar @$a)));
	my $pb = int(rand(max(1, scalar @$b)));
	my @child = (
		(map { [$_->[0], $_->[1]] } @{$a}[0 .. $pa]),
		(map { [$_->[0], $_->[1]] } @{$b}[$pb .. $#$b]),
	);
	splice @child, $MAX_LEN if @child > $MAX_LEN;
	return @child >= 2 ? \@child : [map { [$_->[0],$_->[1]] } @$a];
}

my $CROSSOVER_RATE = 0.50;    # aggressive: half of offspring from crossover
my $SHARING_RADIUS = 2;       # outputs differing in <= this many positions are "same niche"

# ============================================================
# FITNESS SHARING (anti-clumping)
# ============================================================
# If 50 programs produce the same output (e.g., the static sieve),
# each gets fitness/50. This flattens local optima and forces the
# population to diversify. Programs must find DIFFERENT solutions
# to maintain high fitness.

sub output_distance {
	my ($a, $b) = @_;
	my $len = max(scalar @$a, scalar @$b);
	return $len if $len == 0;
	my $diff = 0;
	for my $i (0 .. $len-1) {
		my $va = $i < @$a ? $a->[$i] : -99999;
		my $vb = $i < @$b ? $b->[$i] : -99999;
		$diff++ if $va != $vb;
	}
	return $diff;
}

sub apply_fitness_sharing {
	my ($scored_ref) = @_;
	my @scored = @$scored_ref;
	my $n = scalar @scored;

	for my $i (0 .. $n-1) {
		my $niche_count = 0;
		for my $j (0 .. $n-1) {
			my $dist = output_distance($scored[$i]{out}, $scored[$j]{out});
			if ($dist <= $SHARING_RADIUS) {
				# within niche: contribute inversely to distance
				# distance 0 = full share (1.0), distance 1 = 0.5 share, distance 2 = 0.33
				$niche_count += 1.0 / (1 + $dist);
			}
		}
		$scored[$i]{shared_fitness} = $scored[$i]{fitness} / max(1, $niche_count);
	}

	return \@scored;
}

# ============================================================
# CURRICULUM FITNESS FUNCTIONS
# ============================================================

# Stage 1: produce multiple distinct outputs (viability)
sub viability_fitness {
	my @out = @{$_[0]};
	return 0 if @out == 0;
	my %seen; $seen{$_}++ for @out;
	return scalar(@out) * 5 + scalar(keys %seen) * 10 + (@out >= 5 ? 50 : 0);
}

# Stage 2: produce increasing positive values (structure)
sub structure_fitness {
	my @out = @{$_[0]};
	return 0 if @out < 2;
	my $score = scalar(@out) * 3;
	my $inc_count = 0;
	for (1..$#out) {
		if ($out[$_] > $out[$_-1]) { $score += 10; $inc_count++ }
		$score += 5 if $out[$_] > 0;
	}
	$score += 20 if $inc_count == $#out;  # fully increasing bonus
	return $score;
}

# Stage: "Modulo Gym" — force discovery of mod against VARIABLES
# Rewards sequences where x[n] is NOT divisible by x[n-1].
# This teaches the building block for trial division: checking
# divisibility against a changing value, not a constant.
sub modulo_gym_fitness {
	my @out = @{$_[0]};
	return 0 if @out < 3;

	my $score = scalar(@out) * 3;
	my ($inc_count, $nondiv_count) = (0, 0);

	for (1..$#out) {
		# reward increasing positive values
		if ($out[$_] > $out[$_-1] && $out[$_] > 0) {
			$score += 8;
			$inc_count++;
		}
		# heavy reward: current value NOT divisible by previous
		if ($out[$_-1] > 1 && $out[$_] > 1) {
			if ($out[$_] % $out[$_-1] != 0) {
				$score += 20;
				$nondiv_count++;
			}
		}
	}

	$score += 20 if $inc_count == $#out;       # fully increasing bonus
	$score += $nondiv_count * 5 if $nondiv_count > 3;  # sustained non-divisibility
	return $score;
}

# Final stage: target-specific (streak + relative error from grow_v2)
sub target_fitness {
	my @out = @{$_[0]};
	return 0 if @out == 0;

	my $score = 0;
	my $len = min(scalar @out, scalar @TARGET);

	# streak bonus: exponential reward for consecutive correct prefix
	my $streak = 0;
	for (0..$len-1) { last if $out[$_] != $TARGET[$_]; $streak++ }
	$score += ($streak * $streak) * 10;

	# relative error scoring
	for (0..$len-1) {
		my $diff = abs($out[$_] - $TARGET[$_]);
		if ($diff == 0) { $score += 20 }
		else {
			my $div = max(1, abs($TARGET[$_]));
			$score += 20 / (1 + ($diff/$div) * 10);
		}
	}

	# length penalty
	$score -= abs(scalar(@out) - scalar(@TARGET)) * 5;

	return $score;
}

# ============================================================
# CURRICULUM STAGE DEFINITIONS
# ============================================================
my %STAGES = (
	count   => [
		{ name => 'viability', fn => \&viability_fitness, gens => 50 },
		{ name => 'target',    fn => \&target_fitness },
	],
	evens   => [
		{ name => 'viability', fn => \&viability_fitness, gens => 50 },
		{ name => 'target',    fn => \&target_fitness },
	],
	odds    => [
		{ name => 'viability', fn => \&viability_fitness, gens => 50 },
		{ name => 'target',    fn => \&target_fitness },
	],
	powers  => [
		{ name => 'viability', fn => \&viability_fitness, gens => 50 },
		{ name => 'target',    fn => \&target_fitness },
	],
	squares => [
		{ name => 'viability', fn => \&viability_fitness, gens => 50 },
		{ name => 'structure', fn => \&structure_fitness, gens => 100 },
		{ name => 'target',    fn => \&target_fitness },
	],
	fib     => [
		{ name => 'viability', fn => \&viability_fitness, gens => 50 },
		{ name => 'structure', fn => \&structure_fitness, gens => 100 },
		{ name => 'target',    fn => \&target_fitness },
	],
	primes  => [
		{ name => 'viability',   fn => \&viability_fitness,   gens => 100 },
		{ name => 'modulo gym',  fn => \&modulo_gym_fitness,  gens => 300 },
		{ name => 'target',      fn => \&target_fitness },
	],
);

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

# Run curriculum stages
my @stages = @{$STAGES{$targ_name}};
my $gen_offset = 0;
my $best_ever_score = -1;
my $best_ever_genome;

for my $stage_idx (0..$#stages) {
	my $stage = $stages[$stage_idx];
	my $is_final = ($stage_idx == $#stages);
	my $stage_gens = $stage->{gens} || ($MAX_GENS - $gen_offset);
	my $fitness_fn = $stage->{fn};

	printf "=== STAGE %d: %s (%d gens) ===\n", $stage_idx + 1, uc($stage->{name}), $stage_gens;

	my $stagnation = 0;
	my $stage_best = -1;

	for my $g (1..$stage_gens) {
		my $gen = $gen_offset + $g;
		my @scored;

		# evaluate
		for my $genome (@pop) {
			my $out = run_program($genome, scalar(@TARGET) + 5);
			my $fit = $fitness_fn->($out);
			push @scored, { genome => $genome, fitness => $fit, out => $out,
				shared_fitness => $fit };  # default: shared = raw
		}

		# apply fitness sharing in the target stage to break local optima
		if ($is_final) {
			apply_fitness_sharing(\@scored);
		}

		# sort by shared fitness (selection pressure) but track raw for progress
		@scored = sort { $b->{shared_fitness} <=> $a->{shared_fitness} } @scored;

		# find best by RAW fitness for progress tracking
		my $best = $scored[0];
		for my $s (@scored) {
			$best = $s if $s->{fitness} > $best->{fitness};
		}

		# track stage best (by raw fitness)
		if ($best->{fitness} > $stage_best) {
			$stage_best = $best->{fitness};
			$stagnation = 0;

			if ($is_final && $best->{fitness} > $best_ever_score) {
				$best_ever_score = $best->{fitness};
				$best_ever_genome = [ map { [$_->[0],$_->[1]] } @{$best->{genome}} ];

				printf "Gen %d: Score %.1f  Out: [%s]\n",
					$gen, $best->{fitness}, join(',', @{$best->{out}});

				# check generalization
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
			$stagnation++;
		}

		# curriculum stage progress (non-final stages)
		if (!$is_final && $g % 20 == 0) {
			my @sample = @{$best->{out}};
			@sample = @sample[0..min(7,$#sample)] if @sample > 8;
			printf "  [%s] gen %d: best=%.1f  sample=[%s]\n",
				$stage->{name}, $gen, $stage_best, join(',', @sample);
		}

		# extinction event (final stage only)
		if ($is_final && $stagnation > $EXTINCT_THRESH) {
			$stagnation = 0;
			my @keep = map { $scored[$_]{genome} } 0..$ELITE_SIZE-1;
			@pop = @keep;
			# mix fresh randoms with soup fragments
			while (@pop < $POP_SIZE) {
				if (@$soup > 0 && rand() < 0.3) {
					# 30% chance to pull from soup instead of pure random
					my $frag = $soup->[int(rand(@$soup))];
					push @pop, [ map { [$_->[0],$_->[1]] } @{$frag->{genome}} ];
				} else {
					push @pop, random_genome();
				}
			}
			printf "Gen %d: !! EXTINCTION EVENT !!\n", $gen;
			next;
		}

		# non-final stage stagnation: just move on early
		if (!$is_final && $stagnation > 30) {
			printf "  [%s] converged early at gen %d\n", $stage->{name}, $gen;
			last;
		}

		# horizontal gene transfer from soup (final stage)
		if ($is_final && $g % $HGT_INTERVAL == 0 && @$soup > 0) {
			for (1..$HGT_COUNT) {
				my $idx = $ELITE_SIZE + int(rand(@scored - $ELITE_SIZE));
				next if $idx >= @scored;
				my $frag = $soup->[int(rand(@$soup))];
				$scored[$idx]{genome} = inject_fragment($scored[$idx]{genome}, $frag);
			}
		}

		# selection & reproduction (with homologous crossover)
		my @next;
		push @next, $scored[$_]{genome} for 0..$ELITE_SIZE-1;
		my $top = min(50, scalar @scored);
		while (@next < $POP_SIZE) {
			if (rand() < $CROSSOVER_RATE) {
				# homologous crossover + mutation
				my $p1 = $scored[int(rand($top))]{genome};
				my $p2 = $scored[int(rand($top))]{genome};
				push @next, mutate(homologous_cross($p1, $p2));
			} else {
				# asexual reproduction + mutation
				my $parent = $scored[int(rand($top))]{genome};
				push @next, mutate($parent);
			}
		}
		@pop = @next;
	}

	$gen_offset += $stage_gens;
	printf "  [%s] complete. Best score: %.1f\n\n", $stage->{name}, $stage_best;
}

# final report
print "\n" . "=" x 60 . "\n";
if ($best_ever_genome) {
	print_code($best_ever_genome);
	print_summary($best_ever_genome, $gen_offset);
} else {
	print "No solution found in target stage.\n";
	# show best from final population
	my $best_fit = -1;
	my $best_g;
	for my $genome (@pop) {
		my $out = run_program($genome, scalar(@TARGET) + 5);
		my $fit = target_fitness($out);
		if ($fit > $best_fit) { $best_fit = $fit; $best_g = $genome }
	}
	if ($best_g) {
		print "Best effort (score $best_fit):\n";
		print_code($best_g);
		print_summary($best_g, $gen_offset);
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
