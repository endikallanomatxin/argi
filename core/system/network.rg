-- Native addresses are copied values socket handles are private owners.
_NetworkAddress: CStruct = (._bytes: [128]UInt8, ._length: UInt32)

_NetworkAddress implements ImplicitlyCopyable

NetworkAddress: Type = (._native: _NetworkAddress, ._datagram: Bool)

NetworkAddress implements ImplicitlyCopyable

NetworkFamily: Type = (..any, ..ipv4, ..ipv6)

NetworkFamily implements ImplicitlyCopyable

NetworkTransport: Type = (..tcp, ..udp)

NetworkTransport implements ImplicitlyCopyable

_network_init() -> (.status: Int32): CFunction(.symbol = "_argi_network_init")

_network_deinit() -> (): CFunction(.symbol = "_argi_network_deinit")

_network_resolve(
        .host     : &UInt8,
        .length   : UIntNative,
        .port     : UInt16,
        .family   : Int32,
        .datagram : Int32,
        .passive  : Int32,
        .handle   : $&UIntNative
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_network_resolve")

_network_count(.handle: UIntNative) -> (.count: UIntNative): CFunction(
    .symbol = "_argi_network_address_count"
)

_network_get(
        .handle  : UIntNative,
        .index   : UIntNative,
        .address : $&_NetworkAddress
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_network_address_get")

_network_free(.handle: UIntNative) -> (): CFunction(.symbol = "_argi_network_addresses_free")

_network_socket(
        .address   : &_NetworkAddress,
        .operation : Int32,
        .handle    : $&UIntNative
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_network_socket")

_network_accept(.handle: UIntNative, .accepted: $&UIntNative) -> (.status: Int32): CFunction(
    .symbol = "_argi_network_accept"
)

_network_local(.handle: UIntNative, .address: $&_NetworkAddress) -> (.status: Int32): CFunction(
    .symbol = "_argi_network_local_address"
)

_network_port(.address: &_NetworkAddress) -> (.port: UInt16): CFunction(
    .symbol = "_argi_network_port"
)

_network_close(.handle: UIntNative) -> (.status: Int32): CFunction(.symbol = "_argi_network_close")

_network_timeout(.handle: UIntNative, .milliseconds: UInt32) -> (.status: Int32): CFunction(
    .symbol = "_argi_network_timeout"
)

_network_send(
        .handle : UIntNative,
        .bytes  : RawPointer#(.t: UInt8),
        .length : UIntNative,
        .peer   : RawPointer#(.t: _NetworkAddress),
        .sent   : $&UIntNative
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_network_send")

_network_receive(
        .handle   : UIntNative,
        .bytes    : RawPointer#(.t: UInt8),
        .capacity : UIntNative,
        .peer     : $&_NetworkAddress,
        .received : $&UIntNative
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_network_receive")

_network_shutdown(.handle: UIntNative) -> (.status: Int32): CFunction(
    .symbol = "_argi_network_shutdown_write"
)

Network: Type = (._ffi: $&ForeignFunctionInterface, ._ready: Bool)

once Network init(.ffi: $&ForeignFunctionInterface = reach ffi) -> (.result: Network) := {
    assume ffi

    result = (._ffi = ffi, ._ready = _network_init().status == 0)
}

Network deinit(.self: $&Network) -> () := {
    assume ffi := self&._ffi

    if self&._ready { _network_deinit() }
}

..invalid_network_argument
..address_resolution_failed
..socket_open_failed
..socket_accept_failed
..socket_read_failed
..socket_write_failed
..socket_close_failed
..socket_option_failed
..datagram_too_large
..datagram_truncated

ResolvedAddresses: Type = (._network: &Network, ._handle: UIntNative, ._datagram: Bool)

ResolvedAddresses deinit(.self: $&ResolvedAddresses) -> () := {
    assume ffi := self&._network&._ffi
    _network_free(.handle = self&._handle)
}

_network_any() -> (.value: NetworkFamily) := { value = ..any }

_network_tcp() -> (.value: NetworkTransport) := { value = ..tcp }

resolve_addresses(
        .host      : StringView,
        .port      : UInt16,
        .transport : NetworkTransport = _network_tcp(),
        .family    : NetworkFamily    = _network_any(),
        .passive   : Bool             = false,
        .self      : &Network         = reach network,
    ) -> (
        .result : Errable#(
            ResolvedAddresses,
            (..invalid_network_argument, ..address_resolution_failed, ..out_of_memory)
        )
    ) := {
    assume ffi := self&._ffi

    if self&._ready == false {
        result = ..error(.reason = ..address_resolution_failed)
        return
    }

    selected_family :: Int32 = 0

    if is(.value = family, .variant = ..ipv4) { selected_family = 1 }
    if is(.value = family, .variant = ..ipv6) { selected_family = 2 }
    datagram :: Int32 = 0

    if is(.value = transport, .variant = ..udp) { datagram = 1 }
    wildcard :: Int32 = 0

    if passive { wildcard = 1 }
    handle :: UIntNative = 0
    status ::= _network_resolve(
        .host     = host.data
        .length   = host.length
        .port     = port
        .family   = selected_family
        .datagram = datagram
        .passive  = wildcard
        .handle   = $&handle
    ).status

    if status == -2 {
        result = ..error(.reason = ..invalid_network_argument)
        return
    }

    if status == -3 {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    if status != 0 {
        result = ..error(.reason = ..address_resolution_failed)
        return
    }

    result = ..ok(._network = self, ._handle = handle, ._datagram = datagram == 1)
}

length(.self: &ResolvedAddresses) -> (.count: UIntNative) := {
    assume ffi := self&._network&._ffi
    count = _network_count(.handle = self&._handle).count
}

get(
        .self  : &ResolvedAddresses,
        .index : UIntNative
    ) -> (
        .result : Errable#(NetworkAddress, (..out_of_bounds))
    ) := {
    assume ffi := self&._network&._ffi
    native :: _NetworkAddress = (._bytes = zeroed#(.t: [128]UInt8)(), ._length = 0)

    if _network_get(.handle = self&._handle, .index = index, .address = $&native).status != 0 {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    result = ..ok(._native = native, ._datagram = self&._datagram)
}

port(.self: &NetworkAddress, .network: &Network = reach network) -> (.value: UInt16) := {
    assume ffi := network&._ffi
    value = _network_port(.address = &self&._native).port
}

TcpConnection: Type = (._network: &Network, ._handle: UIntNative)

TcpConnection init(
        .address : NetworkAddress,
        .network : &Network        = reach network
    ) -> (
        .result : Errable#(
            TcpConnection,
            (..invalid_network_argument, ..socket_open_failed, ..out_of_memory)
        )
    ) := {
    assume ffi := network&._ffi

    if address._datagram != false {
        result = ..error(.reason = ..invalid_network_argument)
        return
    }

    if network&._ready == false {
        result = ..error(.reason = ..socket_open_failed)
        return
    }

    handle :: UIntNative = 0
    status ::= _network_socket(.address = &address._native, .operation = 0, .handle = $&handle).status

    if status == -3 {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    if status != 0 {
        result = ..error(.reason = ..socket_open_failed)
        return
    }

    result = ..ok(._network = network, ._handle = handle)
}

close(.self: $&TcpConnection) -> (.result: Errable#(Void, (..socket_close_failed))) := {
    assume ffi := self&._network&._ffi
    handle ::= self&._handle
    self&._handle = 0

    if _network_close(.handle = handle).status != 0 {
        result = ..error(.reason = ..socket_close_failed)
        return
    }

    result = ..ok Void()
}

TcpConnection deinit(.self: $&TcpConnection) -> () := { _ = close(self) }

is_open(.self: &TcpConnection) -> (.value: Bool) := { value = self&._handle != 0 }

local_address(
        .self : &TcpConnection
    ) -> (
        .result : Errable#(NetworkAddress, (..socket_option_failed))
    ) := {
    assume ffi := self&._network&._ffi
    native :: _NetworkAddress = (._bytes = zeroed#(.t: [128]UInt8)(), ._length = 0)

    if _network_local(.handle = self&._handle, .address = $&native).status != 0 {
        result = ..error(.reason = ..socket_option_failed)
        return
    }

    result = ..ok(._native = native, ._datagram = false)
}

TcpListener: Type = (._network: &Network, ._handle: UIntNative)

TcpListener init(
        .address : NetworkAddress,
        .network : &Network        = reach network
    ) -> (
        .result : Errable#(
            TcpListener,
            (..invalid_network_argument, ..socket_open_failed, ..out_of_memory)
        )
    ) := {
    assume ffi := network&._ffi

    if address._datagram != false {
        result = ..error(.reason = ..invalid_network_argument)
        return
    }

    if network&._ready == false {
        result = ..error(.reason = ..socket_open_failed)
        return
    }

    handle :: UIntNative = 0
    status ::= _network_socket(.address = &address._native, .operation = 1, .handle = $&handle).status

    if status == -3 {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    if status != 0 {
        result = ..error(.reason = ..socket_open_failed)
        return
    }

    result = ..ok(._network = network, ._handle = handle)
}

close(.self: $&TcpListener) -> (.result: Errable#(Void, (..socket_close_failed))) := {
    assume ffi := self&._network&._ffi
    handle ::= self&._handle
    self&._handle = 0

    if _network_close(.handle = handle).status != 0 {
        result = ..error(.reason = ..socket_close_failed)
        return
    }

    result = ..ok Void()
}

TcpListener deinit(.self: $&TcpListener) -> () := { _ = close(self) }

is_open(.self: &TcpListener) -> (.value: Bool) := { value = self&._handle != 0 }

local_address(
        .self : &TcpListener
    ) -> (
        .result : Errable#(NetworkAddress, (..socket_option_failed))
    ) := {
    assume ffi := self&._network&._ffi
    native :: _NetworkAddress = (._bytes = zeroed#(.t: [128]UInt8)(), ._length = 0)

    if _network_local(.handle = self&._handle, .address = $&native).status != 0 {
        result = ..error(.reason = ..socket_option_failed)
        return
    }

    result = ..ok(._native = native, ._datagram = false)
}

UdpSocket: Type = (._network: &Network, ._handle: UIntNative)

UdpSocket init(
        .address : NetworkAddress,
        .network : &Network        = reach network
    ) -> (
        .result : Errable#(
            UdpSocket,
            (..invalid_network_argument, ..socket_open_failed, ..out_of_memory)
        )
    ) := {
    assume ffi := network&._ffi

    if address._datagram != true {
        result = ..error(.reason = ..invalid_network_argument)
        return
    }

    if network&._ready == false {
        result = ..error(.reason = ..socket_open_failed)
        return
    }

    handle :: UIntNative = 0
    status ::= _network_socket(.address = &address._native, .operation = 2, .handle = $&handle).status

    if status == -3 {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    if status != 0 {
        result = ..error(.reason = ..socket_open_failed)
        return
    }

    result = ..ok(._network = network, ._handle = handle)
}

close(.self: $&UdpSocket) -> (.result: Errable#(Void, (..socket_close_failed))) := {
    assume ffi := self&._network&._ffi
    handle ::= self&._handle
    self&._handle = 0

    if _network_close(.handle = handle).status != 0 {
        result = ..error(.reason = ..socket_close_failed)
        return
    }

    result = ..ok Void()
}

UdpSocket deinit(.self: $&UdpSocket) -> () := { _ = close(self) }

is_open(.self: &UdpSocket) -> (.value: Bool) := { value = self&._handle != 0 }

local_address(
        .self : &UdpSocket
    ) -> (
        .result : Errable#(NetworkAddress, (..socket_option_failed))
    ) := {
    assume ffi := self&._network&._ffi
    native :: _NetworkAddress = (._bytes = zeroed#(.t: [128]UInt8)(), ._length = 0)

    if _network_local(.handle = self&._handle, .address = $&native).status != 0 {
        result = ..error(.reason = ..socket_option_failed)
        return
    }

    result = ..ok(._native = native, ._datagram = true)
}

accept(
        .self : $&TcpListener
    ) -> (
        .result : Errable#(TcpConnection, (..socket_accept_failed, ..out_of_memory))
    ) := {
    assume ffi := self&._network&._ffi
    handle :: UIntNative = 0
    status ::= _network_accept(.handle = self&._handle, .accepted = $&handle).status

    if status == -3 {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    if status != 0 {
        result = ..error(.reason = ..socket_accept_failed)
        return
    }

    result = ..ok(._network = self&._network, ._handle = handle)
}

set_timeout(
        .self         : $&TcpConnection,
        .milliseconds : UInt32
    ) -> (
        .result : Errable#(Void, (..socket_option_failed))
    ) := {
    assume ffi := self&._network&._ffi

    if _network_timeout(.handle = self&._handle, .milliseconds = milliseconds).status != 0 {
        result = ..error(.reason = ..socket_option_failed)
        return
    }

    result = ..ok Void()
}

set_timeout(
        .self         : $&UdpSocket,
        .milliseconds : UInt32
    ) -> (
        .result : Errable#(Void, (..socket_option_failed))
    ) := {
    assume ffi := self&._network&._ffi

    if _network_timeout(.handle = self&._handle, .milliseconds = milliseconds).status != 0 {
        result = ..error(.reason = ..socket_option_failed)
        return
    }

    result = ..ok Void()
}

read(
        .self   : $&TcpConnection,
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(UIntNative, (..socket_read_failed))
    ) := {
    assume ffi := self&._network&._ffi
    size ::= length(&buffer).count
    address :: UIntNative = 0

    if size != 0 { address = UIntNative(.value = data(&buffer).pointer) }
    received :: UIntNative = 0
    peer :: _NetworkAddress = (._bytes = zeroed#(.t: [128]UInt8)(), ._length = 0)

    if [
        _network_receive(
            .handle   = self&._handle
            .bytes    = raw_pointer#(.t: UInt8)(.address = address).raw
            .capacity = size
            .peer     = $&peer
            .received = $&received
        ).status
        != 0
    ] {
        result = ..error(.reason = ..socket_read_failed)
        return
    }

    result = ..ok received
}

write(
        .self   : $&TcpConnection,
        .buffer : ArrayViewRO#(.t: UInt8)
    ) -> (
        .result : Errable#(UIntNative, (..socket_write_failed))
    ) := {
    assume ffi := self&._network&._ffi
    size ::= length(&buffer).count
    address :: UIntNative = 0

    if size != 0 { address = UIntNative(.value = data(&buffer).pointer) }
    sent :: UIntNative = 0

    if [
        _network_send(
            .handle = self&._handle
            .bytes  = raw_pointer#(.t: UInt8)(.address = address).raw
            .length = size
            .peer   = raw_pointer#(.t: _NetworkAddress)(.address = 0).raw
            .sent   = $&sent
        ).status
        != 0
    ] {
        result = ..error(.reason = ..socket_write_failed)
        return
    }

    result = ..ok sent
}

shutdown_write(
        .self : $&TcpConnection
    ) -> (
        .result : Errable#(Void, (..socket_write_failed))
    ) := {
    assume ffi := self&._network&._ffi

    if _network_shutdown(.handle = self&._handle).status != 0 {
        result = ..error(.reason = ..socket_write_failed)
        return
    }

    result = ..ok Void()
}

DatagramReceived: Type = (.count: UIntNative, .peer: NetworkAddress)

DatagramReceived implements ImplicitlyCopyable

send_to(
        .self   : $&UdpSocket,
        .peer   : NetworkAddress,
        .buffer : ArrayViewRO#(.t: UInt8)
    ) -> (
        .result : Errable#(
            UIntNative,
            (..invalid_network_argument, ..datagram_too_large, ..socket_write_failed)
        )
    ) := {
    assume ffi := self&._network&._ffi

    if peer._datagram == false {
        result = ..error(.reason = ..invalid_network_argument)
        return
    }

    size ::= length(&buffer).count
    address :: UIntNative = 0

    if size != 0 { address = UIntNative(.value = data(&buffer).pointer) }
    sent :: UIntNative = 0
    status ::= _network_send(
        .handle = self&._handle
        .bytes  = raw_pointer#(.t: UInt8)(.address = address).raw
        .length = size
        .peer   = raw_pointer#(.t: _NetworkAddress)(.address = UIntNative(.value = &peer._native)).raw
        .sent   = $&sent
    ).status

    if status == -2 {
        result = ..error(.reason = ..datagram_too_large)
        return
    }

    if status != 0 {
        result = ..error(.reason = ..socket_write_failed)
        return
    }

    result = ..ok sent
}

receive_from(
        .self   : $&UdpSocket,
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(DatagramReceived, (..datagram_truncated, ..socket_read_failed))
    ) := {
    assume ffi := self&._network&._ffi
    size ::= length(&buffer).count
    address :: UIntNative = 0

    if size != 0 { address = UIntNative(.value = data(&buffer).pointer) }
    received :: UIntNative = 0
    peer :: _NetworkAddress = (._bytes = zeroed#(.t: [128]UInt8)(), ._length = 0)
    status ::= _network_receive(
        .handle   = self&._handle
        .bytes    = raw_pointer#(.t: UInt8)(.address = address).raw
        .capacity = size
        .peer     = $&peer
        .received = $&received
    ).status

    if status == -2 {
        result = ..error(.reason = ..datagram_truncated)
        return
    }

    if status != 0 {
        result = ..error(.reason = ..socket_read_failed)
        return
    }

    result = ..ok(.count = received, .peer = (._native = peer, ._datagram = true))
}

-- Bulk writes may be partial. This helper retries with the remaining view
-- it reports failure instead of spinning if a nonempty write makes no progress.
write_all(
        .self   : $&TcpConnection,
        .buffer : ArrayViewRO#(.t: UInt8)
    ) -> (
        .result : Errable#(Void, (..socket_write_failed))
    ) := {
    total ::= length(&buffer).count
    written :: UIntNative = 0

    while written < total {
        remaining ::= unwrap_or_abort(
            .value = slice(
                &buffer
                .start = written
                .count = [
                    total
                    - written
                ]
            )
        )
        count ::= write(self, .buffer = remaining)!
        if count == 0 {
            result = ..error(.reason = ..socket_write_failed)
            return
        }
        written = written + count
    }

    result = ..ok Void()
}

TcpConnection implements Reader
TcpConnection implements Writer

read_byte(
        .self : $&TcpConnection
    ) -> (
        .result : Errable#(ReadByte, (..stream_read_failed))
    ) := {
    buffer :: [1]UInt8 = (0)

    match read(self, .buffer = view($&buffer)) {
        ..error _ { result = ..error(.reason = ..stream_read_failed) }
        ..ok count {
            if count == 0 { result = ..ok ..end } else { result = ..ok ..ok buffer[0] }
        }
    }
}

write_byte(
        .self : $&TcpConnection,
        .byte : UInt8
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    buffer: [1]UInt8 = (byte)

    match write_all(self, .buffer = view(&buffer)) {
        ..error _ { result = ..error(.reason = ..stream_write_failed) }
        ..ok _ { result = ..ok Void() }
    }
}

flush(
        .self : $&TcpConnection
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    if self&._handle == 0 {
        result = ..error(.reason = ..stream_flush_failed)
        return
    }

    result = ..ok Void()
}

read_block(
        .self   : $&TcpConnection,
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(UIntNative, (..stream_read_failed))
    ) := {
    match read(self, .buffer = buffer) {
        ..ok count { result = ..ok count }
        ..error _ { result = ..error(.reason = ..stream_read_failed) }
    }
}

write_block(
        .self   : $&TcpConnection,
        .buffer : ArrayViewRO#(.t: UInt8)
    ) -> (
        .result : Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    match write(self, .buffer = buffer) {
        ..ok count { result = ..ok count }
        ..error _ { result = ..error(.reason = ..stream_write_failed) }
    }
}
