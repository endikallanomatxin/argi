main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    bytes ::= zeroed#(.t: [288]UInt8)()
    tracer ::= FixedSizeErrorTracer(.buffer = view($&bytes))
    context: StringView = "context"
    add_context(.self = $&tracer, .location = error_location_id(), .context = context)
    -- Poison the stored context length without changing the location ID.
    -- Reporting must reject the metadata before reading another slot.
    i :: UIntNative = 4
    while i < size_of(.type = ErrorTraceEntry) {
        bytes[i] = 255
        i = i + 1
    }
    writer ::= to_virtual#(Writer)($&system.terminal&.stderr)
    report(.self = $&tracer, .writer = $&writer)
}
