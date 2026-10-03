# Deterministic randomness

`Pcg32(.seed: UInt64)` creates a local, implicitly copyable PRNG value. It
uses PCG XSH-RR 64/32 with a 64-bit state and the fixed single-stream increment
1442695040888963407. Its multiplier is 6364136223846793005; state arithmetic
is modulo 2^64. This is a non-cryptographic generator, independent of system
entropy, locale, allocation, and foreign calls. See the
[PCG algorithm description](https://www.pcg-random.org/pdf/hmc-cs-2014-0905.pdf).

All `UInt64` seeds are accepted, including zero and the maximum. Initialization
starts at zero, advances once, adds the seed modulo 2^64, and advances again.
The constructor returns `Pcg32` directly. `reseed(.self: $&Pcg32, .seed: UInt64)`
restores the same initial state as a fresh constructor with that seed.

The same seed and sequence of operations produce the same results across
supported targets. Changing the generator algorithm or its draw order would
change this contract. Copying a generator snapshots its current state;
each copy can advance independently. All generation operations receive a
mutable reference, so state dependencies remain explicit.

```rg
main() -> (.status_code: Int32 = 0) := {
    generator ::= Pcg32(.seed = 42)
    first ::= next_uint32(.self = $&generator).value
    bounded ::= unwrap_or_abort(.value = uniform_uint32(
        .self = $&generator, .upper_bound = 100)).result
    unit ::= next_float64(.self = $&generator).value
}
```

## Operations and draw order

A draw applies XSH-RR to the previous state and advances the recurrence once.

| Operation | Output | Draws |
| --- | --- | --- |
| `next_uint32(.self)` | Every `UInt32` bit pattern | 1 |
| `next_uint64(.self)` | First word in the high 32 bits, second in the low bits | 2 |
| `next_bool(.self)` | Whether the word's top bit is set | 1 |
| `next_float16(.self)` | Top 11 bits divided by 2^11 | 1 |
| `next_float32(.self)` | Top 24 bits divided by 2^24 | 1 |
| `next_float64(.self)` | Top 53 bits of a two-word value divided by 2^53 | 2 |
| `uniform_uint32(.self, .upper_bound)` | Integer in `[0, upper_bound)` | 1 per attempt |
| `uniform_uint64(.self, .upper_bound)` | Integer in `[0, upper_bound)` | 2 per attempt |

Each operation returns `.value`, except the two bounded operations, which
return `.result: Errable<UInt32/UInt64, invalid_range>`. Floats lie on equally
spaced binary grids in `[0, 1)`, including zero and excluding one; every grid
value is exactly representable in the requested width.

Bounded generation rejects words below `2^width % upper_bound` before taking
the remainder, avoiding modulo bias. An upper bound of one still consumes an
attempt and returns zero. A zero bound returns `invalid_range` without
consuming state. A rejection may consume further draws; the next operation
continues after the successful attempt.

`Pcg32` has no global default instance or implicit seed. The `System.rand_gen`
capability placeholder remains separate from deterministic state; obtaining
operating-system entropy is an independent capability operation.
