Packet : CStruct = (
    .value: CDouble
    .count: CInt
    .context: RawPointer#(.t: Void)
)
Packet implements ImplicitlyCopyable

argi_callback_add(.left: CInt, .right: CInt) -> (.result: CInt)
    : CFunction(.export = true) := {
    result = left + right
}

argi_callback_packet(.packet: Packet) -> (.result: Packet)
    : CFunction(.export = true) := {
    result = (
        .value = packet.value + packet.value
        .count = packet.count + 3
        .context = packet.context
    )
}

_exercise_callbacks() -> (.result: CInt)
    : CFunction(.symbol = "argi_exercise_callbacks")

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    status_code = _exercise_callbacks()
}
