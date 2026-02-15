# Growing Code

A random program generation pipeline from January 2009. The idea: define a tiny instruction set simple enough that random byte sequences produce valid, compilable programs — a foundation for evolutionary / genetic programming.

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

## The Pipeline

```
random.pl --> nums.pl --> toc.pl --> gcc --> run
 (bytes)    (toten src)   (C code)  (binary)
```

1. **`random.pl N`** — Generate N random bytes (0-255)
2. **`nums.pl`** — Convert pairs of bytes into toten instructions (first byte selects opcode, second becomes operand)
3. **`toc.pl`** — Compile a toten program to C (goto-based control flow, numbered variables, accumulator pointer)

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

## What Was Never Built

The "growing" part. The missing evolutionary loop:

- Fitness function — evaluate program output against a goal
- Selection — keep the best programs
- Mutation / crossover — breed new programs from survivors
- Automation — tie the generate-compile-run-evaluate cycle together

The language was deliberately designed so that random byte sequences produce valid programs. The next step would have been to evolve them.
