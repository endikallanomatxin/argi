# Integer utilities

`integer_limits(.value)` returns the minimum and maximum in the operand's
integer type, including target-sized `UIntNative` bounds.

`round_down#(.t)(.value, .multiple)` and `round_up#(.t)(.value, .multiple)`
accept unsigned integers and any positive multiple. Zero reports
`invalid_multiple`; rounding up additionally reports `out_of_range` when
the rounded value cannot be represented. Already rounded values succeed,
including the maximum value with a multiple of one.

Unsigned `bit_length`, `count_ones`, `count_leading_zeros`,
`count_trailing_zeros`, `reverse_bits`, and `is_power_of_two` take explicit
`.t` and `.value`. Counts use `UIntNative`. Zero has bit length and population
count zero, and leading/trailing zero counts equal to the operand width.
Bit reversal includes the entire operand width. These operations need no
allocation or capabilities. Their portable implementations use bounded
integer arithmetic; hardware intrinsic lowering remains a possible optimization.

## Floating-point classification

`classify_float#(.t)(.value)` returns `FloatClass`: zero, subnormal, normal,
infinity or NaN. `float_sign_bit` reports the stored sign, including negative
zero and signed NaNs. `is_finite`, `is_infinite` and `is_nan` provide Boolean
queries. These functions inspect the IEEE representation of `Float16`,
`Float32` and `Float64`, preserving distinctions that comparisons would lose.
