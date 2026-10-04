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

Readonly byte views support unsigned lexicographic `compare`, `equals`,
`find(.pattern)` and `find(.byte)`, `find_last(.pattern)`, `contains`,
`starts_with`, and `ends_with`. Searches return optional byte offsets. Empty
patterns match at zero in forward search and at the view length in reverse
search. Prefix and suffix checks accept an empty pattern. Searches allocate
no storage and accept embedded NUL bytes; sequence search has worst-case work
proportional to view length times pattern length.

`slice(.self, .start, .count)` checks the entire requested subrange before
forming a borrowed view. Empty slices at the end are valid; starts past the
end and counts exceeding the remaining extent return `out_of_bounds`.
