SocketAddress#(.Socket: Type): Contract = (
    .local : (.self: &Socket, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(NetworkAddress, (..socket_option_failed))
    )
)

SocketTimeout#(.Socket: Type): Contract = (
    .configure_timeout : (
        .self: $&Socket, .milliseconds: UInt32, .error_tracer: $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(Void, (..socket_option_failed)))
)

local_address := #(.Socket: Type: SocketAddress#(Socket)) (
    .self: &Socket, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(NetworkAddress, (..socket_option_failed))) {
    assume error_tracer

    result = SocketAddress#(Socket).local(.self = self)
}

set_timeout := #(.Socket: Type: SocketTimeout#(Socket)) (
    .self: $&Socket, .milliseconds: UInt32, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Void, (..socket_option_failed))) {
    assume error_tracer

    result = SocketTimeout#(
        Socket
    ).configure_timeout(.self = self, .milliseconds = milliseconds)
}

implement SocketAddress#(TcpConnection) (.local = _local_address_TcpConnection)

implement SocketAddress#(TcpListener) (.local = _local_address_TcpListener)

implement SocketAddress#(UdpSocket) (.local = _local_address_UdpSocket)

implement SocketTimeout#(TcpConnection) (.configure_timeout = _set_timeout_TcpConnection)

implement SocketTimeout#(UdpSocket) (.configure_timeout = _set_timeout_UdpSocket)
