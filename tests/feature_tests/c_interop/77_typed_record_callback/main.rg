Packet : CStruct = (.value: CDouble, .count: CInt, .context: RawPointer#(.t: Void))
Packet implements ImplicitlyCopyable
Transformer(.packet: Packet) -> (.result: Packet) : CFunctionPointer

transform(.packet: Packet) -> (.result: Packet) : CFunction := {
    result = (.value = packet.value, .count = packet.count + 1, .context = packet.context)
}

_packet() -> (.result: Packet) : CFunction(.symbol = "argi_typed_callback_packet")

_probe(.callback: Transformer) -> (.result: CInt) : CFunction(.symbol = "argi_typed_callback_probe")

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    callback := Transformer(.function = transform)
    packet := _packet()
    result := callback(.packet = packet)
    if result.value != packet.value or result.count != 9 or result.context.address != 0 {
        status_code = 10
        return
    }
    status_code = _probe(.callback = callback)
}
