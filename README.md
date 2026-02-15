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

### Results

| Target | evolve.pl | grow_v2.pl |
|--------|-----------|------------|
| count `[1..10]` | **Perfect** gen 7, 4 instructions | **Perfect** gen 12 |
| evens `[2,4,6,8,10]` | **Perfect** gen 129, 7 instructions | — |
| odds `[1,3,5,7,9]` | **Perfect** gen 124 (3 islands), 5 instructions | — |
| powers `[1,2,4,8,16]` | **Perfect** ~gen 100, 8 instructions | **Perfect** gen 412 |
| squares `[1,4,9,16,25]` | 5/16 partial | **Perfect** gen 37 |
| fibonacci `[1,1,2,3,5,8,13]` | 11/18 partial (5 islands + swap) | **Perfect** gen 207 |
| primes `[2,3,5,7,11]` | 2/16 partial | 5/14 partial |

The classic engine excels at targets with simple loop structures. The semantic engine cracks harder targets like fibonacci and squares that require multi-register coordination. Primes remains unsolved — it needs nested loops (trial division) which neither engine has discovered.

## Tools

| File | Description |
|------|-------------|
| `toten.pl` | **Driver script** — unified CLI for all tools below |
| `evolve.pl` | Classic genetic algorithm — crossover, tournament selection, island model |
| `grow_v2.pl` | Semantic mutation engine — relative fitness, streak bonus, extinction events |
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
