Packet : CStruct = (.value: CDouble, .count: CInt, .context: RawPointer#(.t: Void))
Packet implements ImplicitlyCopyable
Transformer(.packet: Packet) -> (.result: Packet) : CFunctionPointer

transform(.packet: Packet) -> (.result: Packet) : CFunction := {
    result = (.value = packet.value, .count = packet.count + 1, .context = packet.context)
}

_probe(.callback: Transformer) -> (.result: CInt) : CFunction(.symbol = "argi_typed_callback_probe")

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    callback := Transformer(.function = transform)
    status_code = _probe(.callback = callback)
}
