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

Helpers borrow streams and buffers. They allocate no storage. Generic failures
retain stream reasons; TCP's direct socket operations retain socket reasons.
