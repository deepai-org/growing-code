#!/usr/bin/perl
# grow_v2.pl - Evolutionary Code Grower (Semantic Mutation & Relative Fitness)
#
# Addresses the "Fibonacci Cliff" by using semantic mutation operators
# and relative error scoring to smooth the fitness landscape.
#
# Usage: perl grow_v2.pl [target] [generations]
# Example: perl grow_v2.pl fib 2000

use strict;
use warnings;
use List::Util qw(min max sum shuffle);
use Time::HiRes qw(time);

# --- Configuration ---
my $POP_SIZE    = 200;
my $ELITE_SIZE  = 10;
my $MAX_GENS    = $ARGV[1] || 2000;
my $MAX_LEN     = 64;   # Max instructions
my $INIT_LEN    = 16;   # Starting length
my $MAX_STEPS   = 5000; # Run limit per execution

# --- The Instruction Set ---
# We weight these for initialization to bias towards useful structures (Theory 3)
my @OPS_WEIGHTED = (
    ('mark') x 4,  # Anchors for loops
    ('inc')  x 3,  # Basic counting
    ('add')  x 3,  # Accumulation
    ('print')x 3,  # Output
    ('up')   x 3,  # Loops
    ('setv') x 2,  # Variable movement
    ('if')   x 2,  # Logic
    qw(sub mul div mod zero setc swap ifnot down stop)
);

# Map for decoding byte -> op
my @OPS_MAP = qw(mark inc add sub mul div mod zero setv setc swap print if ifnot up down stop);

# --- Target Generation ---
my $targ_name = $ARGV[0] || 'count';
my @TARGET;
my @EXTENDED; # Generalization set
my $TRAIN_LIMIT;

my %generators = (
    count   => sub { 1 .. $_[0] },
    squares => sub { map { $_*$_ } 1 .. $_[0] },
    fib     => sub { my $n=shift; my @f=(1,1); push @f, $f[-1]+$f[-2] while @f<$n; @f },
    primes  => sub {
        my $n=shift; my @p; my $c=2;
        while(@p<$n){
            my $ok=1;
            for(2..sqrt($c)){ if($c%$_==0){$ok=0;last} }
            push @p,$c if $ok; $c++;
        } @p
    },
    powers  => sub { map { 2**($_-1) } 1..$_[0] },
);

if ($generators{$targ_name}) {
    # Train on first N, test on N+M
    my $N = ($targ_name eq 'fib' || $targ_name eq 'primes') ? 9 : 12;
    @EXTENDED = $generators{$targ_name}->($N + 5);
    @TARGET   = @EXTENDED[0..$N-1];
    $TRAIN_LIMIT = $N;
} else {
    die "Unknown target. Options: count, squares, fib, primes, powers\n";
}

print "Target: $targ_name\n";
print "Training on: [" . join(',', @TARGET) . "]\n";
print "Testing on:  [" . join(',', @EXTENDED) . "]\n\n";

# --- The Virtual Machine ---
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

        if    ($op eq 'mark') { $acc = $arg; } # Also acts as label
        elsif ($op eq 'inc')  { $reg{$arg}++; }
        elsif ($op eq 'add')  { $reg{$acc} += ($reg{$arg}//0); }
        elsif ($op eq 'sub')  { $reg{$acc} -= ($reg{$arg}//0); }
        elsif ($op eq 'mul')  { $reg{$acc} *= ($reg{$arg}//0); }
        elsif ($op eq 'div')  { $reg{$acc} = int($reg{$acc} / ($reg{$arg}//1)) if ($reg{$arg}//0) != 0; }
        elsif ($op eq 'mod')  { $reg{$acc} %= $reg{$arg} if ($reg{$arg}//0) != 0; }
        elsif ($op eq 'zero') { $reg{$arg} = 0; }
        elsif ($op eq 'setv') { $reg{$acc} = ($reg{$arg}//0); } # acc = reg[arg]
        elsif ($op eq 'setc') { $reg{$acc} = $arg; }            # acc = const
        elsif ($op eq 'swap') { my $t = ($reg{$acc}//0); $reg{$acc}=($reg{$arg}//0); $reg{$arg}=$t; }
        elsif ($op eq 'print'){
            push @out, ($reg{$arg}//0);
            return \@out if @out >= $limit_out;
        }
        elsif ($op eq 'if')   { $pc += 2 if ($reg{$arg}//0) == 0; } # skip next if 0
        elsif ($op eq 'ifnot'){ $pc += 2 if ($reg{$arg}//0) != 0; } # skip next if !0
        elsif ($op eq 'stop') { last; }
        elsif ($op eq 'up' || $op eq 'down') {
            # Jump logic
            my $dir = ($op eq 'up') ? -1 : 1;
            my $scan = $pc;
            my $found = 0;
            # Look for 'mark N'
            while (1) {
                $scan += $dir;
                last if $scan < 0 || $scan >= @ins;
                if ($ins[$scan][0] eq 'mark' && $ins[$scan][1] == $arg) {
                    $pc = $scan;
                    $found = 1;
                    last;
                }
            }
            next if $found; # Jump taken, don't inc PC
        }
        $pc++;
    }
    return \@out;
}

# --- Fitness Function (Theory 8) ---
sub calc_fitness {
    my ($output, $target_ref) = @_;
    my @out = @$output;
    my @targ = @$target_ref;

    return 0 if @out == 0;

    my $score = 0;
    my $len = min(scalar @out, scalar @targ);

    # 1. Prefix Streak Bonus (Critical for sequence logic)
    my $streak = 0;
    for (my $i=0; $i<$len; $i++) {
        last if $out[$i] != $targ[$i];
        $streak++;
    }
    # Exponential reward for getting the chain right
    $score += ($streak * $streak) * 10;

    # 2. Relative Error (Smoother gradients for large numbers)
    for (my $i=0; $i<$len; $i++) {
        my $diff = abs($out[$i] - $targ[$i]);
        if ($diff == 0) {
            $score += 20;
        } else {
            # Relative error scoring:
            # If target is 144 and we got 140, diff is 4.
            # 4 / 144 is small.
            my $divisor = max(1, abs($targ[$i]));
            my $rel_err = $diff / $divisor;
            $score += 20 / (1 + $rel_err * 10);
        }
    }

    # 3. Penalty for wrong length (too short or too long)
    my $len_diff = abs(scalar(@out) - scalar(@targ));
    $score -= $len_diff * 5;

    return $score;
}

# --- Semantic Mutation (Theory 7) ---
sub mutate {
    my $genome = shift;
    my @g = map { [$_->[0], $_->[1]] } @$genome; # deep copy

    my $r = rand();

    if ($r < 0.10) {
        # INSERT: Add a random instruction
        return \@g if @g >= $MAX_LEN;
        my $pos = int(rand(@g+1));
        splice @g, $pos, 0, [$OPS_WEIGHTED[rand @OPS_WEIGHTED], int(rand(10))];
    }
    elsif ($r < 0.20) {
        # DELETE: Remove an instruction
        return \@g if @g <= 2;
        splice @g, int(rand(@g)), 1;
    }
    elsif ($r < 0.50) {
        # MODIFY OPERAND: Change the number/register (Soft mutation)
        my $idx = int(rand(@g));
        # Bias towards small changes (+/- 1) or random flip
        if (rand() < 0.5) {
            $g[$idx][1] = ($g[$idx][1] + (rand()<.5?1:-1)) % 10;
        } else {
            $g[$idx][1] = int(rand(10));
        }
    }
    elsif ($r < 0.70) {
        # MODIFY OPCODE: Change the instruction, keep the operand
        my $idx = int(rand(@g));
        $g[$idx][0] = $OPS_WEIGHTED[rand @OPS_WEIGHTED];
    }
    elsif ($r < 0.85) {
        # SWAP: Exchange two instructions (Preserves logic components)
        my $i = int(rand(@g));
        my $j = int(rand(@g));
        ($g[$i], $g[$j]) = ($g[$j], $g[$i]);
    }
    elsif ($r < 0.95) {
        # DUP BLOCK: Copy a small chunk (Helps find loops/patterns)
        return \@g if @g >= $MAX_LEN - 3;
        my $len = 2 + int(rand(3)); # length 2-4
        my $src = int(rand(@g - $len));
        my $dst = int(rand(@g));
        return \@g if $src < 0;
        my @chunk = @g[$src .. $src+$len-1];
        # Deep copy chunk
        @chunk = map { [ $_->[0], $_->[1] ] } @chunk;
        splice @g, $dst, 0, @chunk;
    }

    # Trim if over max
    splice @g, $MAX_LEN if @g > $MAX_LEN;

    return \@g;
}

sub random_genome {
    my @g;
    for (1..$INIT_LEN) {
        push @g, [$OPS_WEIGHTED[rand @OPS_WEIGHTED], int(rand(10))];
    }
    return \@g;
}

# --- Main Evolution Loop ---

my @pop;
push @pop, random_genome() for 1..$POP_SIZE;

my $best_ever_score = -1;
my $stagnation = 0;

for my $gen (1..$MAX_GENS) {
    my @scored;

    # 1. Evaluate
    for my $g (@pop) {
        my $out = run_program($g, scalar @TARGET + 5);
        my $fit = calc_fitness($out, \@TARGET);
        push @scored, { genome => $g, fitness => $fit, out => $out };
    }

    # 2. Sort
    @scored = sort { $b->{fitness} <=> $a->{fitness} } @scored;

    my $best = $scored[0];

    # 3. Report
    if ($best->{fitness} > $best_ever_score) {
        $best_ever_score = $best->{fitness};
        $stagnation = 0;
        print "Gen $gen: New Best! Score: $best->{fitness}\n";
        print "  Out: [" . join(',', @{$best->{out}}) . "]\n";

        # Check generalization
        my $full_out = run_program($best->{genome}, scalar @EXTENDED);
        my $gen_fit = calc_fitness($full_out, \@EXTENDED);
        my $match_count = 0;
        for(0..$#EXTENDED) { last if ($full_out->[$_]//-999) != $EXTENDED[$_]; $match_count++; }

        print "  Gen Check: matched $match_count / " . scalar(@EXTENDED) . "\n";
        if ($match_count == scalar @EXTENDED) {
            print "\nSUCCESS! Algorithm Discovered.\n";
            print_code($best->{genome});
            exit;
        }
    } else {
        $stagnation++;
    }

    # 4. Extinction Event (Theory 6)
    if ($stagnation > 50) {
        print "Gen $gen: !! EXTINCTION EVENT !! (Stagnation > 50)\n";
        # Keep elites, kill the rest, replace with fresh randoms
        @pop = ();
        push @pop, $scored[$_]{genome} for 0..$ELITE_SIZE-1;
        push @pop, random_genome() for 1..($POP_SIZE - $ELITE_SIZE);
        $stagnation = 0;
        next;
    }

    # 5. Selection & Reproduction
    my @next_gen;

    # Elitism
    push @next_gen, $scored[$_]{genome} for 0..$ELITE_SIZE-1;

    # Tournament & Mutate
    while (@next_gen < $POP_SIZE) {
        # Tournament size 5
        my $p1 = $scored[int(rand(50))]{genome}; # Pick from top 50 (soft selection)

        # Clone and Mutate
        my $child = mutate($p1);
        push @next_gen, $child;
    }

    @pop = @next_gen;
}

sub print_code {
    my $g = shift;
    print "------------------------\n";
    for my $i (0..$#$g) {
        print "$i\t$g->[$i][0] $g->[$i][1]\n";
    }
    print "------------------------\n";
}
