# Networking

`System.network` exposes blocking address resolution, TCP, and UDP. Operations
receive a `&Network`, either explicitly or through `assume network`. The
capability retains its ordinary FFI dependency; sockets and resolution owners
borrow it and must be cleaned up before it ends.

```rg
main(.system: System) -> () := {
    assume writer ::= $&system.terminal&.stderr
    assume network := system.network
    addresses ::= resolve_addresses(.host = "localhost", .port = 8080)!!!
    address ::= get(.self = &addresses, .index = 0)!!!
    connection ::= TcpConnection(.address = address)!!!
    bytes: [4]UInt8 = (112, 105, 110, 103)
    write_all(.self = $&connection, .buffer = view(.array = &bytes))!!!
    shutdown_write(.self = $&connection)!!!
}
```

## Addresses

`resolve_addresses(.host, .port, .transport, .family, .passive, .self)` returns an
owning `ResolvedAddresses`. Transport defaults to `..tcp`; `..udp` selects
UDP. Family defaults to `..any`, with `..ipv4` and `..ipv6` available. Port is
`UInt16`. Host names must contain no NUL byte and at most 253 bytes. Names and
numeric addresses are resolved by the selected platform's resolver. An empty
host with `.passive = true` selects wildcard binding addresses; without passive
mode it selects loopback addresses.

`length` reports the number of addresses; checked `get(.index)` copies a
`NetworkAddress`. This value owns its address bytes and remains valid after the
resolution owner is cleaned up. It records the selected transport, so a TCP
address cannot be used to construct a UDP socket or vice versa. Address bytes
and native handles are private. `port(.self, .network)` reads the numeric port.
The initial API exposes IP endpoints, not Unix-domain sockets or raw protocols.

## TCP

`TcpConnection(.address, .network)` connects to one endpoint.
`TcpListener(.address, .network)` binds and listens; `accept(.self)` returns a
new independent connection. `local_address` copies an owner's bound endpoint,
including the port selected by the OS when binding port zero. A connection does
not borrow its listener, so listener cleanup does not close accepted connections.

`read(.self, .buffer)` fills an initialized mutable byte view and returns the
number read. A nonempty read returning zero means EOF. Empty buffers perform no
receive and return zero. `write(.self, .buffer)` accepts a readonly byte view and
may write only a prefix; `write_all` retries until every byte has been sent or
an error occurs. A write error can follow successful prefix writes.
`shutdown_write` ends the sending direction without closing the receiving side.

Connections also implement `Reader` and `Writer`. Their byte operations map
socket failures to the ordinary stream reasons. `flush` checks that the
connection is open; there is no additional Argi buffer to flush.

## UDP

`UdpSocket(.address, .network)` binds a datagram endpoint. `send_to(.self,
.peer, .buffer)` sends one datagram and returns its byte count; the baseline
accepts at most 65,507 bytes. `receive_from(.self, .buffer)` receives one datagram
and returns `DatagramReceived(.count, .peer)`. Empty datagrams are successful
messages, not EOF. An insufficient destination reports `..datagram_truncated`
and consumes the datagram; the buffer may contain its prefix. It never reports a
truncated datagram as a complete successful message.

## Lifetimes and failures

Socket owners and `ResolvedAddresses` are movable and cannot be copied
implicitly. Automatic cleanup releases native resources exactly once. Explicit
`close` is idempotent, clears a socket's handle even on close failure, and permits
ordinary later cleanup. Operations on a closed socket return errors. Cleanup
ignores close errors; explicit `close` lets the caller inspect them. No socket
handle or native allocation is a safe reference or an allocation receipt.

`set_timeout(.self, .milliseconds)` configures native receive/send timeouts for a
connection or UDP socket. Zero restores blocking operation without a timeout.
These timeouts do not bound DNS resolution, connection establishment, or accept.
Resolution, opening, accepting, reads, writes, options, and close have distinct
error reasons; argument, allocation, oversized-datagram, and truncation failures
remain distinguishable. The baseline does not expose platform errno values.

Native adapters cover POSIX Linux/macOS and Windows Winsock. Async operation,
readiness polling, TLS, HTTP, and cancellation are outside this baseline.
