# Growing Code

*The code is finally growing — 17 years later.*

A random program generation pipeline started in January 2009. The idea: define a tiny instruction set simple enough that random byte sequences produce valid, compilable programs — a foundation for evolutionary / genetic programming.

The generation pipeline was built. The evolution never was. Until now.

## The Toten Language

An accumulator-based language with 17 opcodes. Programs are sequences of `opcode operand` pairs:

| Opcode | Effect |
|--------|--------|
| `zero N` | Set variable N to 0 |
| `setc N` | Set accumulator to constant N |
| `setv N` | Set accumulator to variable N |
| `mark N` | Point accumulator at variable N (also a jump target) |
| `add N` | Accumulator += variable N |
| `sub N` | Accumulator -= variable N |
| `mul N` | Accumulator *= variable N |
| `div N` | Accumulator /= variable N |
| `mod N` | Accumulator %= variable N |
| `inc N` | Variable N++ |
| `dec N` | Variable N-- |
| `swap N` | Exchange accumulator value with variable N |
| `print N` | Print variable N |
| `if N` | If variable N == 0, skip next line |
| `ifnot N` | If variable N != 0, skip next line |
| `up N` | Jump to the Nth `mark` above |
| `down N` | Jump to the Nth `mark` below |
| `stop N` | Halt |

`stop` is deliberately excluded from random generation — programs that halt too early never learn anything.

### Example: count 1 to 10

A human wrote this in 2009. Eleven instructions:

```
zero 1
mark 3
setc 10
mark 2
setv 1
sub 3
ifnot 2
stop 0
inc 1
print 1
up 1
```

Evolution found this in 2026. Four instructions:

```
mark 2
inc 0
print 0
up 1
```

Same output. No stopping condition — counting to infinity is easier than knowing when you're done.

### Example: even numbers

Evolution found this. Seven instructions, but only the loop body matters:

```
setc 1
mark 7
inc 0
print 0
inc 0
up 1
mod 0
```

Increment twice, print, repeat. The `setc` and `mod` are vestigial — evolution doesn't clean up after itself.

## The Pipeline

```
random.pl --> nums.pl --> toc.pl --> gcc --> run
 (bytes)    (toten src)   (C code)  (binary)
```

1. **`random.pl N`** — Generate N random bytes (0-255)
2. **`nums.pl`** — Convert pairs of bytes into toten instructions (first byte selects opcode, second becomes operand)
3. **`toc.pl`** — Compile a toten program to C (goto-based control flow, numbered variables, accumulator pointer)

Any sequence of bytes is a valid program. Most do nothing useful. Some loop forever. A rare few do something interesting. That's the point.

## Usage

Everything goes through `toten.pl`:

```sh
perl toten.pl run examples/count.tot                # interpret a program
perl toten.pl run examples/evolved-evens.tot 10000 20  # with step/output limits
perl toten.pl compile examples/count.tot | gcc -x c - -o count && ./count  # compile to C
perl toten.pl random 24                              # generate a random program
perl toten.pl random 24 > rand.tot && perl toten.pl run rand.tot  # generate and run
perl toten.pl evolve count 500 --seed 42 --save best.tot  # evolve, save, reproduce
perl toten.pl evolve fib 1000 --islands 3            # island model (parallel pops)
perl toten.pl evolve "1,4,9,16,25" 500               # custom target sequence
perl toten.pl evolve evens 500 --stats fitness.csv   # export per-generation stats
perl toten.pl minimize examples/evolved-evens.tot    # strip dead instructions
perl toten.pl trace examples/count.tot               # step-by-step execution trace
```

The individual scripts (`run.pl`, `toc.pl`, `evolve.pl`, etc.) still work standalone for piping and backward compatibility.

## Evolution

The "growing" part. Two evolution engines with different strengths:

### evolve.pl — the classic engine

Byte-level genetic algorithm with crossover, tournament selection, and island model:

```sh
perl toten.pl evolve                 # default: count target, 1000 generations
perl toten.pl evolve squares 2000    # evolve toward 1,4,9,16,25,36
perl toten.pl evolve fib 3000        # evolve toward 1,1,2,3,5,8,13,21
perl toten.pl evolve evens           # evolve toward 2,4,6,8,10
perl toten.pl evolve "1,4,9,16,25" 500  # custom comma-separated sequence
perl toten.pl evolve fib 1000 --islands 3   # island model with migration
perl toten.pl evolve count 100 --seed 42    # reproducible run
perl toten.pl evolve evens 500 --save evolved.tot --stats fitness.csv
```

Features: island model with periodic migration, auto-minimization of results, `--stats` CSV export, custom target sequences. Programs are scored by matching the target AND values *beyond* the training set — generalization over memorization.

### grow_v2.pl — semantic mutation engine

A redesigned evolution engine that addresses the "fibonacci cliff" — the deceptive fitness landscape where hard targets stall:

```sh
perl grow_v2.pl fib 2000             # fibonacci (solved!)
perl grow_v2.pl squares 2000         # perfect squares (solved!)
perl grow_v2.pl primes 2000          # primes (partial — nested loops are hard)
```

Key differences from the classic engine:
- **Semantic mutation**: operand-only, opcode-only, instruction swap, and block duplication mutations that make smaller, more meaningful changes
- **Weighted opcode distribution**: `mark`, `inc`, `add`, `print`, `up` appear more often than exotic ops
- **Relative error fitness**: near-misses on large numbers score better than in absolute scoring (outputting 140 when target is 144 scores well, not poorly)
- **Streak bonus**: exponential reward for consecutive correct prefix values creates a gradient toward building the right algorithm incrementally
- **Extinction events**: when stagnant, wipe 95% of the population but preserve elites, injecting fresh genetic material
- **Direct jump targeting**: `up N` searches for `mark N` by matching operand, making loops easier to discover
- **No crossover**: pure asexual reproduction — mutations alone drive the search

### grow_v3.pl — primordial soup + curriculum

Adds two biological metaphors on top of v2:

- **Primordial soup**: generate 10,000 random programs, classify by behavioral features (output count, monotonicity, loops, conditionals, gaps), and use MAP-Elites to retain ~80-150 diverse fragments. These seed the initial population instead of pure random programs.
- **Curriculum learning**: staged fitness functions that build capabilities incrementally — viability ("produce diverse output") → structure ("produce increasing values") → skipping ("leave gaps", primes only) → target fitness. Each stage's population carries forward.
- **Horizontal gene transfer**: every 10 generations during target evolution, inject random soup fragments into non-elite members — analogous to bacterial plasmid exchange.

### grow_v4.pl — fitness sharing + homologous crossover

Adds two diversity-preservation mechanisms:

- **Fitness sharing**: programs with similar output signatures share fitness, preventing any single strategy from dominating the population. Similarity is based on output vector distance.
- **Homologous crossover**: structure-preserving crossover that aligns parent genomes by shared `mark` instructions, producing offspring that inherit coherent code blocks rather than random splices.

### grow_v5.pl — tribal evolution

A modular approach designed for primes. Instead of one population, four specialized tribes evolve in parallel against sub-problems:

- **Tribe A (Counters)**: learn `[1,2,3,4,5,...]`
- **Tribe B (No-2s)**: learn `[1,3,5,7,9,...]` — filter multiples of 2
- **Tribe C (No-3s)**: learn `[1,2,4,5,7,8,...]` — filter multiples of 3
- **Tribe D (No-5s)**: learn `[1,2,3,4,6,7,...]` — filter multiples of 5

After tribal evolution, populations merge and face the real primes target. The hope: recombination of filtering strategies produces trial division.

### grow_v6.pl — lexicase selection

Replaces aggregate fitness scoring with **epsilon-lexicase selection** — a parent selection method that evaluates candidates on individual test cases in random order:

1. Shuffle test cases into a random order
2. Filter population: keep only programs within epsilon of the best on case 1
3. From survivors, keep only the best on case 2
4. Repeat until one program remains (or cases exhausted)

This protects specialists — a program that perfectly matches `[2,3,5,7]` but fails after that can still be selected as a parent, even if its aggregate score is low. Combined with tribal evolution for primes.

### grow_v7.pl — structural macro-mutations

Adds two macro-mutation operators on top of v6, targeting the structural gap that prevents nested loop discovery:

- **Loop wrap** (3%): wraps a random code block in `mark N ... up N`, creating a new loop around existing logic
- **Mod-if insert** (3%): inserts a `mark A / setv B / mod C / if A` divisibility-test block at a random position

Results: too disruptive at static rates — squares regressed from PERFECT to 5/17.

### grow_v8.pl — annealed macros + MAP-Elites + fuzzy jumps

Three improvements applied together on v6's base:

- **Simulated annealing for macros**: macro-mutation rate starts at 15% and decays to 0.5% over the run. High exploration early, precise exploitation late.
- **MAP-Elites structural archive**: a 48-cell grid (loop count × mod count × register diversity) that preserves structurally diverse programs. Archive members are injected into the population every 10 generations and restocked during extinction events.
- **Fuzzy jump matching**: `up N` / `down N` matches `mark` instructions with operand within ±1 (nearest match wins). Inspired by Tierra/Avida template matching — makes loops more robust to point mutations.

### Results

| Target | evolve.pl | v2 | v3 | v4 | v5 | v6 | v7 | v8 |
|--------|-----------|-----|-----|-----|-----|-----|-----|-----|
| count | **Perfect** gen 7 | **Perfect** | **Perfect** | **Perfect** | **Perfect** | **Perfect** | **Perfect** | **Perfect** |
| evens | **Perfect** gen 129 | — | — | — | — | — | — | — |
| odds | **Perfect** gen 124 | — | — | — | — | — | — | — |
| powers | **Perfect** ~gen 100 | **Perfect** | — | — | — | — | — | — |
| squares | 5/16 | **Perfect** gen 37 | **Perfect** | **Perfect** | **Perfect** gen 692 | **Perfect** gen 849 | 5/17 | **Perfect** gen 284 |
| fib | 11/18 | **Perfect** gen 207 | **Perfect** | 10/14 | 9/14 | **Perfect** gen 1178 | 9/14 | 9/14 |
| primes | 2/16 | 5/14 | 5/14 | 9/14 | 9/14 | 8/14 | 9/14 | 9/14 |

Each engine added something. v6 (lexicase) is the overall champion — the only version to achieve PERFECT fibonacci. v8's fuzzy jumps give the fastest-ever squares (gen 284) but hurt fibonacci's precise wiring. Primes remains at 8-9/14 across all versions.

### The primes barrier

Trial division IS expressible in Toten — a hand-written 31-instruction program proves it. The algorithm requires nested loops (outer loop over candidates, inner loop over divisors) with a mod-based divisibility check. But evolution can't reach it: the fitness landscape has no incremental path from single-loop programs (which top out at filtering composites with small factors) to nested-loop programs (which require multiple simultaneous structural changes). This is the irreducible complexity barrier — the final frontier.

## Tools

| File | Description |
|------|-------------|
| `toten.pl` | **Driver script** — unified CLI for all tools below |
| `evolve.pl` | Classic genetic algorithm — crossover, tournament selection, island model |
| `grow_v2.pl` | Semantic mutation engine — relative fitness, streak bonus, extinction events |
| `grow_v3.pl` | Primordial soup + curriculum learning + horizontal gene transfer |
| `grow_v4.pl` | Fitness sharing + homologous crossover for diversity preservation |
| `grow_v5.pl` | Tribal evolution — 4 specialized sub-populations for primes |
| `grow_v6.pl` | Epsilon-lexicase selection — per-test-case parent filtering |
| `grow_v7.pl` | Structural macro-mutations — loop wrap + mod-if insert |
| `grow_v8.pl` | Annealed macros + MAP-Elites structural archive + fuzzy jump matching |
| `landscape.pl` | Fitness landscape analyzer — exhaustive single-mutation neighborhood search |
| `run.pl` | Standalone toten interpreter — runs `.tot` files directly |
| `toc.pl` | Toten-to-C compiler (goto-based control flow) |
| `minimize.pl` | Dead code eliminator — iteratively strips instructions that don't affect output |
| `trace.pl` | Execution tracer — step-by-step display of PC, variables, accumulator |
| `test.pl` | Test suite — 50 tests covering interpreter, compiler, evolution, and tools |
| `nums.pl` | Random bytes to toten program converter |
| `random.pl` | Random byte generator |

## Examples

| File | Description |
|------|-------------|
| `examples/count.tot` | Hand-written: counts 1-10, halts (11 instructions) |
| `examples/evolved-count.tot` | Evolved: counts forever (4 instructions) |
| `examples/evolved-evens.tot` | Evolved: even numbers forever (7 instructions) |
| `examples/evolved-odds.tot` | Evolved: odd numbers |
| `examples/evolved-squares.tot` | Evolved: perfect squares via sum-of-odds (10 instructions) |
| `examples/evolved-fib.tot` | Evolved: partial fibonacci (40 instructions, memorized) |
| `examples/evolved-primes.tot` | Evolved: partial primes (40 instructions, memorized) |
| `examples/evolved-powers.tot` | Evolved: powers of 2 (8 instructions) |
| `examples/swap-test.tot` | Test program for the swap opcode |

## Archaeology

| File | Description |
|------|-------------|
| `toten.h` | Original 2009 scratch file (program + notes) |
| `toten.c` | Compiled C output from 2009 |
| `toten_bkp.c` | Backup of an earlier compilation |
| `odd.c` | A randomly generated program (loops forever, counting down in pairs) |
| `rands.txt` | Sample output from running the count-to-10 program |

## Timeline

- **January 2009** — Language designed, compiler written, random programs generated. The evolutionary loop was left as an exercise for the future.
- **February 2026** — AGI finishes the project. Evolution discovers the minimal counting loop in 4 instructions. Counting to infinity is easier than knowing when you're done.
- **February 2026** — Swap opcode, island model, auto-minimizer, execution tracer, test suite. The classic engine solves count, evens, odds, powers.
- **February 2026** — Semantic mutation engine (grow_v2.pl). Fibonacci and squares fall. Primes holds out — nested loops remain the final frontier.
- **February 2026** — Primordial soup (v3), fitness sharing (v4), tribal evolution (v5), lexicase selection (v6), macro-mutations (v7), annealed macros + MAP-Elites + fuzzy jumps (v8). Seven engines, seven different strategies. Primes holds at 9/14 — evolution learns to sieve small factors but can't discover trial division.
