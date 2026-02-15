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

A human wrote this in 2009. Eleven instructions. Could evolution rediscover it?

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

Compile and run the example program:

```sh
head -12 toten.h | perl toc.pl | gcc -x c - -o example && ./example
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
perl evolve.pl              # default: 500 generations, target 1..10
perl evolve.pl 1000         # 1000 generations
perl evolve.pl 1000 5       # target 1..5
```

It uses a built-in toten interpreter (no gcc needed), tournament selection, crossover, and mutation. Programs are scored by how closely their output matches the target sequence.

In one run, at generation 183, evolution discovered a counting loop — `inc`, `print`, `mark`, `up` — and produced a perfect `1, 2, 3, 4, 5, 6, 7, 8, 9, 10`. It just never figured out how to stop. Counting to infinity is easier than knowing when you're done.

## Files

| File | Description |
|------|-------------|
| `toten.h` | Hand-written toten program (counts 1-10) |
| `toten.c` | Compiled C output of the above |
| `toten_bkp.c` | Backup of an earlier compilation |
| `odd.c` | A randomly generated program (loops forever, counting down in pairs) |
| `toc.pl` | Toten-to-C compiler |
| `nums.pl` | Random bytes to toten program converter |
| `random.pl` | Random byte generator |
| `rands.txt` | Sample output from running the count-to-10 program |
| `evolve.pl` | Genetic algorithm — evolves toten programs toward a target output |

## Timeline

- **January 2009** — Language designed, compiler written, random programs generated. The evolutionary loop was left as an exercise for the future.
- **February 2026** — AGI finishes the project.
