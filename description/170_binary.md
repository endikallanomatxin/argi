# Binary byte operations

`ByteOrder` selects `..little` or `..big`, independently of the compilation
target. `read_uint16`, `read_uint32`, and `read_uint64` decode an unsigned
integer from a readonly byte view at `.offset` (default zero). Matching
`write_uint16`, `write_uint32`, and `write_uint64` accept an initialized mutable
byte view and `.value`. Every operation requires explicit `.order`.

Offsets can be unaligned. Insufficient ranges return `out_of_bounds`, including
oversized offsets; arithmetic never depends on adding an unchecked offset and
width. Failed writes leave all bytes unchanged. No native record layout,
alignment, pointer reinterpretation, allocator, or FFI capability is required.

`ByteReader(.bytes)` and `ByteWriter(.bytes)` borrow those views and start at
position zero. Their matching integer operations accept `.self` instead of
`.bytes`/`.offset`, advancing only after success. `position` and `remaining`
report byte counts; checked `skip(.self, .count)` advances without accessing
bytes. Failure preserves position and, for writes, the destination.

Cursors retain backing-storage lifetimes. They do not own the buffer or extend
its lifetime. They intentionally expose no unchecked cursor construction or
arbitrary native memory serialization.
