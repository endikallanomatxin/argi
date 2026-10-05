# Byte streams

`Reader` and `Writer` provide byte operations. `BlockReader` and `BlockWriter`
provide `read_block` and `write_block` with byte views and a returned count.
For a nonempty read, zero means EOF. Writes may make partial progress; zero
for nonempty input means no progress. Neither operation silently flushes.
Writers accept readonly input; `as_readonly` converts a mutable view without
copying or changing its backing lifetime. Empty views require no data pointer.

Files and TCP use their native block operations. Process streams and buffered
wrappers bridge their byte interfaces to the block contracts. Both static
contracts and `Virtual` handles support the helpers below. A custom block
implementation must return a count within the supplied view's extent.

- `read_exact(.self, .buffer)` fills the destination, or reports
  `unexpected_eof`/`stream_read_failed`. Failure can leave a written prefix.
- `write_all(.self, .buffer)` retries partial writes and reports a stream write
  error if a nonempty write makes no progress. Failure can follow prefix writes.
- `copy_stream(.reader, .writer, .buffer)` copies until EOF using caller-owned,
  initialized scratch storage and returns the total. An empty scratch view is
  `invalid_stream_buffer`; unrepresentable totals report `size_overflow`.
  It neither closes nor flushes either endpoint and imposes no total size limit.
- `read_until(.self, .buffer, .delimiter)` consumes bytes into bounded storage.
  Its `ReadUntil` result contains `.count` and `.termination` (`delimiter`,
  `end`, or `limit`). The delimiter is consumed but not stored. A limit stops
  before reading another byte; zero capacity performs no read. Full buffers
  therefore need another call to discover a following delimiter or EOF.

These helpers borrow streams and buffers and allocate no storage. Generic
failures retain stream reasons; TCP's direct socket operations retain socket
reasons.

## Transfers with destination storage

`transfer_stream(.reader, .writer)` is a free function taking a `BlockReader`
or its `Virtual` handle and a concrete `Writer`. It transfers until EOF and returns the number of newly accepted
bytes. Dispatch considers both inputs; no transfer buffer is supplied by the
caller. An ordinary writer uses one initialized byte of local storage.

With a `BufferedWriter`, the function reads directly into the free portion of
that writer's initialized buffer. Pending output stays before newly read bytes;
a full buffer is flushed before the next read. A zero-capacity wrapper delegates
to its underlying writer. The transfer borrows both endpoints, allocates nothing,
and leaves their owners open. Success does not promise a flushed destination;
call `flush` explicitly to check the final output.

Only successful reads increase the pending length. On a read failure, previously
accepted bytes remain pending; bytes written into free space by the failed read
are ignored. Writes and flushes retain the buffered writer's existing failure
policy, which discards pending bytes on failure to avoid repeating uncertain
native progress. Stream errors and unrepresentable totals are reported through
an `Errable`; failure may follow consumed input and already written output.

## Bounded consumption

`copy_stream_limited(.reader, .writer, .buffer, .limit)` copies at most `limit`
bytes with initialized caller scratch. Its `StreamCopyResult` contains `.count`
and `.termination: StreamCopyEnd` (`end` or `limit`). Every read request fits
both scratch and the remaining limit. Reaching the limit performs no lookahead;
exact EOF at that boundary is therefore reported as `limit`. A zero limit
performs no stream operations and accepts empty scratch. Nonzero limits require
nonempty scratch or return `invalid_stream_buffer`. Partial reads and writes
are retried. Read/write errors may follow consumed or written prefixes; the
helper neither closes nor flushes endpoints.

`read_all_limited(.self, .buffer, .limit, .allocator)` reads a complete stream
into an owning `String`, preserving arbitrary bytes, including embedded NULs.
It imposes no UTF-8 validation. Scratch must be initialized and nonempty,
including at limit zero. A source ending within the limit returns the owner.
After accumulating exactly the limit, it reads one byte into scratch to check
EOF. An extra byte returns `size_limit_exceeded` and is consumed; no remaining
excess is read. A zero limit accepts only an already exhausted source.

The owner's capacity stays within `max(1, limit)`, plus String's trailing NUL
byte. Growth can temporarily retain both old and new allocations, so peak
storage is at most two such allocations plus caller scratch and allocator
bookkeeping. Growth reserves the next requested chunk before consuming it.
A limit that cannot leave room for the trailing NUL reports `size_overflow`
before allocation or reading. `out_of_memory`, `stream_read_failed`, and limit
errors release accumulated ownership; they return no partial owner and do not
rewind the stream. Static and virtual block readers support both operations.

## Memory streams

`ByteReader` implements `Reader` and `BlockReader`; `ByteWriter` implements
`Writer` and `BlockWriter`. They compose with exact operations and bounded
stream copies while retaining their borrowed initialized byte storage.

Reader exhaustion reports byte EOF or a block count of zero. Block operations
transfer the smaller of the requested extent and remaining storage. A writer
with no capacity reports `stream_write_failed` for nonempty writes; writing an
empty block succeeds with zero. Failed byte writes preserve position and
storage. `flush` succeeds without side effects. Binary and stream operations
share the same cursor position and require no allocator or FFI capability.

`LimitedReader#(.t)(.source, .limit)` borrows a `BlockReader` and implements
`BlockReader`. Its `read_block` clips the destination to the remaining limit
and decrements that limit only by successfully read bytes. Zero remaining
limit returns zero without calling the source. Source EOF can occur before
the limit. `remaining` reports the unused allowance. Once the adapter's loan
ends, the underlying source resumes at the next unread byte; no lookahead is
consumed. Errors propagate and do not decrement the allowance.

## Bounded borrowed lines

`read_line(.self, .buffer)` returns an optional `ByteLine` in an `Errable`.
A line borrows the supplied initialized buffer through readonly `.bytes`;
`.terminated` distinguishes LF termination from a final unterminated line.
LF is consumed but excluded. A CR immediately before LF is also excluded;
a CR at EOF remains data. Empty lines are values; EOF with no data returns
none. Byte contents are not UTF-8 validated.

Buffer capacity counts bytes before LF, including a possible CR. An exact
fit succeeds after one byte of lookahead. Longer input reports `line_too_long`
after consuming the first overflowing byte; the buffer holds the prefix and
the source remains after that byte. Errors can therefore consume input and
modify the buffer. Reusing the buffer changes earlier borrowed line contents;
copy a line when it must survive later reads. This operation allocates nothing.
