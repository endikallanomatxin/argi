-- Native addresses are copied values socket handles are private owners.
_NetworkAddress: CStruct = (._bytes: [128]UInt8, ._length: UInt32)

implement ImplicitlyCopyable#(_NetworkAddress) ()

NetworkAddress: Type = (._native: _NetworkAddress, ._datagram: Bool)

implement ImplicitlyCopyable#(NetworkAddress) ()

NetworkFamily: Type = (..any, ..ipv4, ..ipv6)

implement ImplicitlyCopyable#(NetworkFamily) ()

NetworkTransport: Type = (..tcp, ..udp)

implement ImplicitlyCopyable#(NetworkTransport) ()

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
) -> (.status: Int32): CFunction(.symbol = "_argi_network_resolve")

_network_count(.handle: UIntNative) -> (.count: UIntNative): CFunction(
    .symbol = "_argi_network_address_count"
)

_network_get(.handle: UIntNative, .index: UIntNative, .address: $&_NetworkAddress) -> (
    .status : Int32
): CFunction(.symbol = "_argi_network_address_get")

_network_free(.handle: UIntNative) -> (): CFunction(.symbol = "_argi_network_addresses_free")

_network_socket(.address: &_NetworkAddress, .operation: Int32, .handle: $&UIntNative) -> (
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

_network_close(.handle: UIntNative) -> (.status: Int32): CFunction(
    .symbol = "_argi_network_close"
)

_network_timeout(.handle: UIntNative, .milliseconds: UInt32) -> (.status: Int32): CFunction(
    .symbol = "_argi_network_timeout"
)

_network_send(
    .handle : UIntNative,
    .bytes  : RawPointer#(.t: UInt8),
    .length : UIntNative,
    .peer   : RawPointer#(.t: _NetworkAddress),
    .sent   : $&UIntNative
) -> (.status: Int32): CFunction(.symbol = "_argi_network_send")

_network_receive(
    .handle   : UIntNative,
    .bytes    : RawPointer#(.t: UInt8),
    .capacity : UIntNative,
    .peer     : $&_NetworkAddress,
    .received : $&UIntNative
) -> (.status: Int32): CFunction(.symbol = "_argi_network_receive")

_network_shutdown(.handle: UIntNative) -> (.status: Int32): CFunction(
    .symbol = "_argi_network_shutdown_write"
)

Network: Type = (._ffi: $&ForeignFunctionInterface, ._ready: Bool)

once _acquire_network := (.args: (.ffi: $&ForeignFunctionInterface = reach ffi)) -> (
    .result : Network
) {
    ffi ::= args.ffi

    assume ffi

    result = (._ffi = ffi, ._ready = _network_init().status == 0)
}

implement Init#(Network, (.ffi: $&ForeignFunctionInterface = reach ffi)) (
    .Result : Type = Network
    .init   = _acquire_network
)

implement Deinit#(Network) (
    .deinit = (.self: $&Network) -> () {
        assume ffi := self&._ffi

        if self&._ready { _network_deinit() }
    }
)

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

implement Deinit#(ResolvedAddresses) (
    .deinit = (.self: $&ResolvedAddresses) -> () {
        assume ffi := self&._network&._ffi
        _network_free(.handle = self&._handle)
    }
)

_network_any() -> (.value: NetworkFamily) := { value = ..any }

_network_tcp() -> (.value: NetworkTransport) := { value = ..tcp }

resolve_addresses(
    .host      : StringView,
    .port      : UInt16,
    .transport : NetworkTransport = _network_tcp(),
    .family    : NetworkFamily    = _network_any(),
    .passive   : Bool = false,
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
        .host     = host._data
        .length   = host._length
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

address_at := (.self: &ResolvedAddresses, .index: UIntNative) -> (
    .result : Errable#(NetworkAddress, (..out_of_bounds))
) {
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

implement Init#(TcpConnection, (.address: NetworkAddress, .network: &Network = reach network)) (
    .Result : Type = Errable#(
        TcpConnection, (..invalid_network_argument, ..socket_open_failed, ..out_of_memory)
    )
    .init = (.args: (.address: NetworkAddress, .network: &Network = reach network)) -> (
        .result : Result
    ) {
        address ::= args.address
        network ::= args.network

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
        status ::= _network_socket(
            .address = &address._native, .operation = 0, .handle = $&handle
        ).status

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
)

_close_TcpConnection(.self: $&TcpConnection) -> (
    .result : Errable#(Void, (..socket_close_failed))
) := {
    assume ffi := self&._network&._ffi
    handle ::= self&._handle
    self&._handle = 0

    if _network_close(.handle = handle).status != 0 {
        result = ..error(.reason = ..socket_close_failed)
        return
    }

    result = ..ok Void()
}

implement Deinit#(TcpConnection) (
    .deinit = (.self: $&TcpConnection) -> () {
        _ = close(self)
    }
)

_is_open_TcpConnection(.self: &TcpConnection) -> (.ok: Bool) := { ok = self&._handle != 0 }

_local_address_TcpConnection(.self: &TcpConnection) -> (
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

implement Init#(TcpListener, (.address: NetworkAddress, .network: &Network = reach network)) (
    .Result : Type = Errable#(
        TcpListener, (..invalid_network_argument, ..socket_open_failed, ..out_of_memory)
    )
    .init = (.args: (.address: NetworkAddress, .network: &Network = reach network)) -> (
        .result : Result
    ) {
        address ::= args.address
        network ::= args.network

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
        status ::= _network_socket(
            .address = &address._native, .operation = 1, .handle = $&handle
        ).status

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
)

_close_TcpListener(.self: $&TcpListener) -> (.result: Errable#(Void, (..socket_close_failed))) := {
    assume ffi := self&._network&._ffi
    handle ::= self&._handle
    self&._handle = 0

    if _network_close(.handle = handle).status != 0 {
        result = ..error(.reason = ..socket_close_failed)
        return
    }

    result = ..ok Void()
}

implement Deinit#(TcpListener) (
    .deinit = (.self: $&TcpListener) -> () {
        _ = close(self)
    }
)

_is_open_TcpListener(.self: &TcpListener) -> (.ok: Bool) := { ok = self&._handle != 0 }

_local_address_TcpListener(.self: &TcpListener) -> (
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

implement Init#(UdpSocket, (.address: NetworkAddress, .network: &Network = reach network)) (
    .Result : Type = Errable#(
        UdpSocket, (..invalid_network_argument, ..socket_open_failed, ..out_of_memory)
    )
    .init = (.args: (.address: NetworkAddress, .network: &Network = reach network)) -> (
        .result : Result
    ) {
        address ::= args.address
        network ::= args.network

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
        status ::= _network_socket(
            .address = &address._native, .operation = 2, .handle = $&handle
        ).status

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
)

_close_UdpSocket(.self: $&UdpSocket) -> (.result: Errable#(Void, (..socket_close_failed))) := {
    assume ffi := self&._network&._ffi
    handle ::= self&._handle
    self&._handle = 0

    if _network_close(.handle = handle).status != 0 {
        result = ..error(.reason = ..socket_close_failed)
        return
    }

    result = ..ok Void()
}

implement Deinit#(UdpSocket) (
    .deinit = (.self: $&UdpSocket) -> () {
        _ = close(self)
    }
)

_is_open_UdpSocket(.self: &UdpSocket) -> (.ok: Bool) := { ok = self&._handle != 0 }

_local_address_UdpSocket(.self: &UdpSocket) -> (
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

accept(.self: $&TcpListener) -> (
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

_set_timeout_TcpConnection(.self: $&TcpConnection, .milliseconds: UInt32) -> (
    .result : Errable#(Void, (..socket_option_failed))
) := {
    assume ffi := self&._network&._ffi

    if _network_timeout(.handle = self&._handle, .milliseconds = milliseconds).status != 0 {
        result = ..error(.reason = ..socket_option_failed)
        return
    }

    result = ..ok Void()
}

_set_timeout_UdpSocket(.self: $&UdpSocket, .milliseconds: UInt32) -> (
    .result : Errable#(Void, (..socket_option_failed))
) := {
    assume ffi := self&._network&._ffi

    if _network_timeout(.handle = self&._handle, .milliseconds = milliseconds).status != 0 {
        result = ..error(.reason = ..socket_option_failed)
        return
    }

    result = ..ok Void()
}

_read_tcp(.self: $&TcpConnection, .buffer: ArrayView#(.t: UInt8)) -> (
    .result : Errable#(UIntNative, (..socket_read_failed))
) := {
    assume ffi := self&._network&._ffi
    size ::= length(&buffer).count
    address :: UIntNative = 0

    if size != 0 { address = data(&buffer).pointer | convert#(.to: UIntNative)(_) }
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

_tcp_write(.self: $&TcpConnection, .value: ArrayViewRO#(.t: UInt8)) -> (
    .result : Errable#(UIntNative, (..socket_write_failed))
) := {
    assume ffi := self&._network&._ffi
    size ::= length(&value).count
    address :: UIntNative = 0

    if size != 0 { address = data(&value).pointer | convert#(.to: UIntNative)(_) }
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

implement WriteValue#(TcpConnection, ArrayViewRO#(.t: UInt8)) (
    .Result      : Type = Errable#(UIntNative, (..socket_write_failed))
    .write_value = _tcp_write
)

shutdown_write(.self: $&TcpConnection) -> (.result: Errable#(Void, (..socket_write_failed))) := {
    assume ffi := self&._network&._ffi

    if _network_shutdown(.handle = self&._handle).status != 0 {
        result = ..error(.reason = ..socket_write_failed)
        return
    }

    result = ..ok Void()
}

DatagramReceived: Type = (.count: UIntNative, .peer: NetworkAddress)

implement ImplicitlyCopyable#(DatagramReceived) ()

send_to(.self: $&UdpSocket, .peer: NetworkAddress, .buffer: ArrayViewRO#(.t: UInt8)) -> (
    .result : Errable#(
        UIntNative, (..invalid_network_argument, ..datagram_too_large, ..socket_write_failed)
    )
) := {
    assume ffi := self&._network&._ffi

    if peer._datagram == false {
        result = ..error(.reason = ..invalid_network_argument)
        return
    }

    size ::= length(&buffer).count
    address :: UIntNative = 0

    if size != 0 { address = data(&buffer).pointer | convert#(.to: UIntNative)(_) }
    sent :: UIntNative = 0
    status ::= _network_send(
        .handle = self&._handle
        .bytes  = raw_pointer#(.t: UInt8)(.address = address).raw
        .length = size
        .peer   = raw_pointer#(.t: _NetworkAddress)(
            .address = [&peer._native | convert#(.to: UIntNative)(_)]
        ).raw
        .sent = $&sent
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

receive_from(.self: $&UdpSocket, .buffer: ArrayView#(.t: UInt8)) -> (
    .result : Errable#(DatagramReceived, (..datagram_truncated, ..socket_read_failed))
) := {
    assume ffi := self&._network&._ffi
    size ::= length(&buffer).count
    address :: UIntNative = 0

    if size != 0 { address = data(&buffer).pointer | convert#(.to: UIntNative)(_) }
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

implement Reader#(TcpConnection) (
    .read_byte = (.self: $&TcpConnection) -> (
        .result : Errable#(ReadByte, (..stream_read_failed))
    ) {
        buffer :: [1]UInt8 = (0)

        match read(self, .buffer = view($&buffer)) {
            ..error _ { result = ..error(.reason = ..stream_read_failed) }
            ..ok count {
                if count == 0 { result = ..ok ..end } else { result = ..ok ..ok buffer[0] }
            }
        }
    }
)

implement BlockReader#(TcpConnection) (
    .read_block = (.self: $&TcpConnection, .buffer: ArrayView#(.t: UInt8)) -> (
        .result : Errable#(UIntNative, (..stream_read_failed))
    ) {
        match read(self, .buffer = buffer) {
            ..ok count { result = ..ok count }
            ..error _ { result = ..error(.reason = ..stream_read_failed) }
        }
    }
)

implement BlockWriter#(TcpConnection) (
    .write_block = (.self: $&TcpConnection, .buffer: ArrayViewRO#(.t: UInt8)) -> (
        .result : Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
    ) {
        match write(self, .value = buffer) {
            ..ok count { result = ..ok count }
            ..error _ { result = ..error(.reason = ..stream_write_failed) }
        }
    }
)

implement Writer#(TcpConnection) (
    .write_byte = (.self: $&TcpConnection, .byte: UInt8) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        buffer: [1]UInt8 = (byte)

        match write_all(self, .buffer = view(&buffer)) {
            ..error _ { result = ..error(.reason = ..stream_write_failed) }
            ..ok _ { result = ..ok Void() }
        }
    }

    .flush = (.self: $&TcpConnection) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        if self&._handle == 0 {
            result = ..error(.reason = ..stream_flush_failed)
            return
        }

        result = ..ok Void()
    }
)

implement Closeable#(TcpConnection) (
    .Result         : Type = Errable#(Void, (..socket_close_failed))
    .close_resource = _close_TcpConnection
)

implement OpenState#(TcpConnection) (.check_open = _is_open_TcpConnection)

implement Closeable#(TcpListener) (
    .Result         : Type = Errable#(Void, (..socket_close_failed))
    .close_resource = _close_TcpListener
)

implement OpenState#(TcpListener) (.check_open = _is_open_TcpListener)

implement Closeable#(UdpSocket) (
    .Result         : Type = Errable#(Void, (..socket_close_failed))
    .close_resource = _close_UdpSocket
)

implement OpenState#(UdpSocket) (.check_open = _is_open_UdpSocket)

implement BufferReading#(TcpConnection) (
    .Result : Type = Errable#(UIntNative, (..socket_read_failed))
    .read   = _read_tcp
)
