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

Compile and run a toten program:

```sh
cat examples/count.tot | perl toc.pl | gcc -x c - -o count && ./count
```

Generate and run a random program:

```sh
perl random.pl 24 | perl nums.pl | perl toc.pl | gcc -x c - -o random_prog && ./random_prog
```

Note: random programs may loop forever. Use a timeout:

```sh
perl random.pl 24 | perl nums.pl | perl toc.pl | gcc -x c - -o random_prog && perl -e 'alarm 2; exec "./random_prog"'
```

## Evolution

The "growing" part. `evolve.pl` evolves random toten programs using a genetic algorithm:

```sh
perl evolve.pl              # default: count target, 1000 generations
perl evolve.pl squares 2000 # evolve toward 1,4,9,16,25,36
perl evolve.pl fib 3000     # evolve toward 1,1,2,3,5,8,13,21
perl evolve.pl evens         # evolve toward 2,4,6,8,10
```

Available targets: `count`, `squares`, `fib`, `primes`, `evens`, `odds`, `powers`, or any number N for 1..N.

Programs are scored by how closely their output matches the target. But matching the training set isn't enough — programs are also tested on values *beyond* the target to reward generalization over memorization. A program that hardcodes `[1,4,9]` plateaus; one that actually computes `n*n` keeps scoring. Shorter programs are slightly preferred, so evolution compresses bloated solutions down to their essence.

Genomes start at 24 bytes and can grow up to 80 through insertion mutations — the code literally grows.

### Results

| Target | Best output | Matched | Notes |
|--------|-------------|---------|-------|
| count `[1..10]` | `[1,2,3,...,40]` | 20/20 | **Perfect algorithm** in 4 instructions, gen 7 |
| evens `[2,4,6,8,10]` | `[2,4,6,8,10]` | 5/5 | **Perfect**, gen 59 |
| fibonacci `[1,1,2,3,5,8,13,21]` | `[1,1,2,3,5,7,13,17,34]` | 7/18 | Hits fib numbers but can't sustain the recurrence |
| squares `[1,4,9,16,25,36]` | `[1,4,9,16,16,32,...]` | 6/16 | Finds doubling, not squaring — `n*n` needs nested computation |

## Files

| File | Description |
|------|-------------|
| `examples/count.tot` | Hand-written: counts 1-10, halts (11 instructions) |
| `examples/evolved-count.tot` | Evolved: counts forever (4 instructions) |
| `toten.h` | Original 2009 scratch file (program + notes) |
| `toten.c` | Compiled C output from 2009 |
| `toten_bkp.c` | Backup of an earlier compilation |
| `odd.c` | A randomly generated program (loops forever, counting down in pairs) |
| `toc.pl` | Toten-to-C compiler |
| `nums.pl` | Random bytes to toten program converter |
| `random.pl` | Random byte generator |
| `rands.txt` | Sample output from running the count-to-10 program |
| `evolve.pl` | Genetic algorithm — evolves toten programs toward a target output |

## Timeline

- **January 2009** — Language designed, compiler written, random programs generated. The evolutionary loop was left as an exercise for the future.
- **February 2026** — AGI finishes the project. Evolution discovers the minimal counting loop in 4 instructions. Counting to infinity is easier than knowing when you're done.
