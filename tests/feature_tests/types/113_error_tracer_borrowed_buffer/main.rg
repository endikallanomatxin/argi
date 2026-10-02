Storage : Type = (.aligner: UIntNative, .bytes: [291]UInt8)
ProbeWriter : Type = (.bytes: UIntNative = 0)
ProbeWriter implements Writer
write_byte(.self: $&ProbeWriter, .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self&.bytes = self&.bytes + 1
    result = ..ok Void()
}
flush(.self: $&ProbeWriter) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := { result = ..ok Void() }

main() -> (.status_code: Int32 = 0) := {
    -- The numeric prefix aligns bytes; slicing at one deliberately misaligns
    -- slot headers. Sentinels also cover the unused tail and both boundaries.
    storage ::= Storage(.aligner = 0, .bytes = zeroed#(.t: [291]UInt8)())
    storage.bytes[0] = 77
    storage.bytes[289] = 88
    storage.bytes[290] = 99
    backing ::= view($&storage.bytes)
    buffer ::= unwrap_or_abort(.value = slice(.self = &backing, .start = 1, .count = 289))
    tracer ::= FixedSizeErrorTracer(.buffer = buffer)
    context: StringView = "unaligned context"
    location ::= error_location_id()
    add_context(.self = $&tracer, .location = location, .context = context)
    add_context(.self = $&tracer, .location = location, .context = context)
    add_context(.self = $&tracer, .location = location, .context = context)
    writer ::= ProbeWriter()
    virtual_writer ::= to_virtual#(Writer)($&writer)
    unwrap_or_abort(.value = report(.self = $&tracer, .writer = $&virtual_writer))
    if writer.bytes <= 43 or writer.bytes > 4096 { status_code = 1 return }
    if storage.bytes[0] != 77 or storage.bytes[289] != 88 or storage.bytes[290] != 99 { status_code = 2 return }
    reset_context(.self = $&tracer)
    writer.bytes = 0
    unwrap_or_abort(.value = report(.self = $&tracer, .writer = $&virtual_writer))
    if writer.bytes != 43 { status_code = 3 return }
    deinit(.self = $&tracer)
    storage.bytes[1] = 0

    empty ::= FixedSizeErrorTracer(.buffer = view($&zeroed#(.t: [0]UInt8)()))
    tiny ::= FixedSizeErrorTracer(.buffer = view($&zeroed#(.t: [143]UInt8)()))
    add_context(.self = $&empty, .location = location, .context = context)
    add_context(.self = $&tiny, .location = location, .context = context)
    writer.bytes = 0
    unwrap_or_abort(.value = report(.self = $&empty, .writer = $&virtual_writer))
    empty_count ::= writer.bytes
    writer.bytes = 0
    unwrap_or_abort(.value = report(.self = $&tiny, .writer = $&virtual_writer))
    if empty_count <= 43 or writer.bytes != empty_count { status_code = 4 return }
    reset_context(.self = $&empty)
    reset_context(.self = $&tiny)
    writer.bytes = 0
    unwrap_or_abort(.value = report(.self = $&tiny, .writer = $&virtual_writer))
    if writer.bytes != 43 { status_code = 5 }
}
