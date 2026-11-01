# HTTP/1

Import `network/http` for bounded HTTP/1 request parsing, streamed request bodies,
and fixed-length HTTP/1.1 responses. The protocol works over `BlockReader` and
`BlockWriter`; only the application needs TCP or another transport. Parsing and
streaming use caller-owned initialized storage and require no allocator.

## Requests and storage

`parse_request(.bytes, .limits)` parses a complete request head. Its `RequestHead`
contains borrowed byte views for `method`, `target`, and the exact head `bytes`,
plus `version`, `framing`, and `header_count`. Bytes after the terminating empty
line remain outside the head. Incomplete input returns `unexpected_eof`.

`read_request(.reader, .buffer, .limits)` reads the head into the supplied mutable
byte view. Its result borrows that storage. Keep the storage alive and unchanged
while using the head or any derived header views. The compiler rejects returning
a head backed by local storage that ends at function return.

For a socket, wrap the source in `HttpReader(.reader, .buffer)`. It reads
blocks into caller storage and retains prefetched body bytes. Continue using the
same adapter for body reads; going back to the underlying socket discards access
to its pending input. Large body reads bypass its buffer when no input is pending.
An empty buffer delegates to the source. Plain `read_request` does not overread,
but uses individual byte reads, so direct use on an unbuffered socket is costly.

Input buffering, head storage, and body scratch must be distinct buffers. Neither
views nor adapters own their backing storage. Copy explicitly if data must survive
buffer reuse. Header values and bodies are bytes; they are not assumed to be UTF-8.

`headers(&head)` and `next($&iterator)` iterate all fields, retaining their order
and duplicates. `header(&head, .name)` returns the first case-insensitive match.
Do not combine arbitrary repeated fields with commas. `method_is(&head, .method)`
is case-sensitive; extension methods remain valid tokens.

Origin-form targets (`/path?query`), absolute HTTP(S) targets, and `OPTIONS *` are
accepted. The raw encoded target is preserved. For an absolute target, use its
authority when routing; a conflicting Host field must not override it. Decode
path components only after separating delimiters, using explicit URI utilities
when needed. CONNECT is unsupported. Host validation currently accepts a
conservative subset: reg-names and bracketed hexadecimal IPv6, with optional
ports up to 65535. Encoded hostnames and IPv4-embedded IPv6 are rejected.

## Bodies

Construct `BodyReader(.reader, .head, .limits)` once after reading a head,
with the same limits. Its source type is inferred. It binds framing state to the source and does not retain
the head storage. Keep using it until `body_finished(&body).ok` is true, or close
the connection. Avoid other reads from that source during the message.

`read_body(.self = $&body, .buffer)` returns the number of decoded bytes with
specific HTTP errors. A nonempty buffer returning zero means the body is done.
An empty buffer returns zero without consuming input; use `body_finished` to
check completion in that case. Fixed-length bodies stop exactly at their declared
length and report premature EOF. Chunked bodies validate sizes, extensions,
separators, and trailers, then stop before any following message bytes.

`BodyReader` also implements `BlockReader`, so `read_exact`, `copy_stream`, and
bounded owning reads work unchanged. The stream interface maps HTTP errors to
`stream_read_failed`; `body_failure(&body).reason` retains the first specific
reason. A failed body cannot be resumed. A later direct read returns
`invalid_state` without reading the source. Transfers can have delivered a prefix
before a framing error is discovered; applications must check completion before
committing effects that require a valid complete body.

Trailers are validated and discarded, never merged into the request headers.
Framing, routing, authorization, and content-interpretation fields are rejected
there. Trailer field names are limited to 256 bytes.

## Limits and malformed messages

Default `Limits()` values are:

| Limit | Default |
| --- | ---: |
| Head bytes, including request line and final CRLF | 16384 |
| Header fields | 100 |
| Decoded body bytes | 1048576 |
| Chunk size/extension line bytes, including CRLF | 1024 |
| Trailer section bytes, including final CRLF | 16384 |

The header count limit also applies independently to trailers. Smaller head
storage imposes an additional effective head limit. Limits are checked before
unrepresentable arithmetic or delivery beyond the decoded body budget.

Parsing requires CRLF and validates field names, controls, percent escapes, and
request-target syntax. HTTP/1.1 requires exactly one nonempty valid Host field.
Duplicate Content-Length, even identical values, is rejected. Transfer-Encoding
with Content-Length, repeated transfer encodings, HTTP/1.0 transfer encoding, and
codings other than one `chunked` token are rejected. Requests without framing
have no body; EOF is never used to delimit a request body.

All Expect fields are rejected with `unsupported_expectation`; applications can
send 417 immediately, without waiting for the body. Interim responses are not
implemented. Socket receive/send timeouts bound individual blocking operations,
not a complete request deadline. Set appropriate transport timeouts explicitly.

## Responses

`write_response(.writer, .status = 200, .headers, .body, .head_only = false)`
validates the supplied fields before any output. It generates the status line,
`Connection: close`, and Content-Length. Caller headers cannot override framing.
A response to HEAD must set `head_only` from the request method: it advertises the
representation length without writing the body. Statuses 204, 205, and 304 require
an empty body; 204 and 304 omit Content-Length, and 205 emits zero. Final statuses
200 through 599 are supported.

For a body with known length, `begin_response(.writer, .length, ...)` returns a
borrowed `ResponseWriter`. Send chunks with `write_body(.self, .body)` and check
`finish_response(.self)` after exactly the announced number of bytes. HEAD can
finish without producing representation bytes. Overruns, underruns, repeated
finish, and writes after failure return `invalid_state`. A write failure may
follow emitted bytes and cannot be retried through that response writer.

Writes handle short progress and reject a stalled nonempty write. Serialization
does not close or flush the underlying writer. Wrap a socket in the existing
`BufferedWriter` and explicitly check its flush to coalesce small header writes.
Keep only one active response per stream and close the connection after it.
Unknown-length response streaming, persistent connections, upgrades, TLS, routing,
and concurrent serving are outside this initial API.

## Run the example and tests

From the repository root:

```sh
zig build
./zig-out/bin/argi run more/network/http/examples/server
```

The [example](examples/server/main.rg) listens on `127.0.0.1:8080`, processes one connection at a time, drains
bounded request bodies, and sends a text response. Each connection is closed after
its response. Requests with rejected expectations receive 417 without a body read.
Use a client such as `curl http://127.0.0.1:8080/` or `curl -I http://127.0.0.1:8080/`.

Native Argi tests live beside the implementation in `*_test.rg` files:

```sh
./zig-out/bin/argi test more/network/http
zig build test-http -j16 -Dtest-jobs=16
zig build test-http -j16 -Dtest-jobs=16 -- --filter http_body
```

Tests cover fragmented input, prefetched bytes, framing boundaries, malformed
heads and chunks, limits, partial/stalled writes, streaming response state,
borrowed bytes, a bounded mutation corpus, and a real loopback TCP exchange.
Compiler lifetime rejection coverage remains under `tests/feature_tests/more`.
