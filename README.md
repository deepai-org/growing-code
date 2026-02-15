# Growing Code

*The code is finally growing — 17 years later.*

A random program generation pipeline started in January 2009. The idea: define a tiny instruction set simple enough that random byte sequences produce valid, compilable programs — a foundation for evolutionary / genetic programming.

The generation pipeline was built. The evolution never was. Until now.

## The Toten Language

An accumulator-based language with 16 opcodes. Programs are sequences of `opcode operand` pairs:

| Opcode | Effect |
|--------|--------|
| `zero N` | Set variable N to 0 |
| `setc N` | Set accumulator to constant N |
| `setv N` | Set accumulator to variable N |
| `mark N` | Point accumulator at variable N |
| `add N` | Accumulator += variable N |
| `sub N` | Accumulator -= variable N |
| `mul N` | Accumulator *= variable N |
| `div N` | Accumulator /= variable N |
| `mod N` | Accumulator %= variable N |
| `inc N` | Variable N++ |
| `dec N` | Variable N-- |
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
```

The individual scripts (`run.pl`, `toc.pl`, `evolve.pl`, etc.) still work standalone for piping and backward compatibility.

## Evolution

The "growing" part. Evolve random toten programs toward a target sequence:

```sh
perl toten.pl evolve                 # default: count target, 1000 generations
perl toten.pl evolve squares 2000    # evolve toward 1,4,9,16,25,36
perl toten.pl evolve fib 3000        # evolve toward 1,1,2,3,5,8,13,21
perl toten.pl evolve evens           # evolve toward 2,4,6,8,10
```

Save the best evolved program and reproduce a run:

```sh
perl toten.pl evolve evens 500 --save evolved.tot   # export best as .tot file
perl toten.pl evolve count 100 --seed 42            # reproducible run
perl toten.pl evolve fib 2000 --seed 7 --save fib.tot  # both
```

The saved `.tot` file works with both `run` and `compile` — the full round trip.

Available targets: `count`, `squares`, `fib`, `primes`, `evens`, `odds`, `powers`, or any number N for 1..N.

Programs are scored by how closely their output matches the target. But matching the training set isn't enough — programs are also tested on values *beyond* the target to reward generalization over memorization. A program that hardcodes `[1,4,9]` plateaus; one that actually computes `n*n` keeps scoring. Shorter programs are slightly preferred, so evolution compresses bloated solutions down to their essence.

Genomes start at 24 bytes and can grow up to 80 through insertion mutations — the code literally grows.

When fitness stagnates for 50 generations, the mutation rate triples temporarily to escape local optima, then resets when improvement resumes.

### Results

| Target | Best output | Matched | Notes |
|--------|-------------|---------|-------|
| count `[1..10]` | `[1,2,3,...,40]` | 20/20 | **Perfect algorithm** in 4 instructions, gen 7 |
| evens `[2,4,6,8,10]` | `[2,4,6,...,70]` | 15/15 | **Perfect algorithm** in 7 instructions, gen 129 |
| fibonacci `[1,1,2,3,5,8,13,21]` | `[1,1,2,3,5,7,13,17,34]` | 7/18 | Hits fib numbers but can't sustain the recurrence |
| squares `[1,4,9,16,25,36]` | `[1,4,9,16,16,32,...]` | 6/16 | Finds doubling, not squaring — `n*n` needs nested computation |

## Files

| File | Description |
|------|-------------|
| `toten.pl` | **Driver script** — unified CLI for run, compile, evolve, random |
| `evolve.pl` | Genetic algorithm — evolves toten programs toward a target output |
| `run.pl` | Standalone toten interpreter — runs `.tot` files directly, no compiler needed |
| `toc.pl` | Toten-to-C compiler |
| `nums.pl` | Random bytes to toten program converter |
| `random.pl` | Random byte generator |
| `examples/count.tot` | Hand-written: counts 1-10, halts (11 instructions) |
| `examples/evolved-count.tot` | Evolved: counts forever (4 instructions) |
| `examples/evolved-evens.tot` | Evolved: even numbers forever (7 instructions) |
| `toten.h` | Original 2009 scratch file (program + notes) |
| `toten.c` | Compiled C output from 2009 |
| `toten_bkp.c` | Backup of an earlier compilation |
| `odd.c` | A randomly generated program (loops forever, counting down in pairs) |
| `rands.txt` | Sample output from running the count-to-10 program |

## Timeline

- **January 2009** — Language designed, compiler written, random programs generated. The evolutionary loop was left as an exercise for the future.
- **February 2026** — AGI finishes the project. Evolution discovers the minimal counting loop in 4 instructions. Counting to infinity is easier than knowing when you're done.
