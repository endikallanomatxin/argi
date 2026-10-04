Source: Type = (.bytes: ArrayViewRO#(.t: UInt8), .position: UIntNative, .calls: UIntNative)

Source implements Reader
Source implements BlockReader

read_byte(.self: $&Source) -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed))) := {
    if self&.position == length(.self = &self&.bytes).count {
        result = ..ok ..end
        return
    }
    byte ::= unwrap_or_abort(.value = get_ro_ref(.self = &self&.bytes, .index = self&.position))
    self&.position = self&.position + 1
    result = ..ok ..ok byte&
}

read_block(
        .self   : $&Source,
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(.t: UIntNative, .reasons: (..stream_read_failed))
    ) := {
    self&.calls = self&.calls + 1
    if length(.self = &buffer).count == 0 {
        result = ..ok 0
        return
    }
    match read_byte(.self = self)! {
        ..end { result = ..ok 0 }
        ..ok byte {
            pointer ::= unwrap_or_abort(.value = get_rw_ref(.self = $&buffer, .index = 0))
            pointer&= byte
            result = ..ok 1
        }
    }
}

Sink: Type = (.bytes: ArrayView#(.t: UInt8), .position: UIntNative, .stalled: Bool)

Sink implements BlockWriter

write_block(
        .self   : $&Sink,
        .buffer : ArrayViewRO#(.t: UInt8)
    ) -> (
        .result : Errable#(.t: UIntNative, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) := {
    if self&.stalled or length(.self = &buffer).count == 0 {
        result = ..ok 0
        return
    }
    byte ::= unwrap_or_abort(.value = get_ro_ref(.self = &buffer, .index = 0))
    target ::= unwrap_or_abort(.value = get_rw_ref(.self = $&self&.bytes, .index = self&.position))
    target&= byte&
    self&.position = self&.position + 1
    result = ..ok 1
}

main() -> !Void = ..ok Void() := {
    input: [4]UInt8 = (65, 0, 66, 10)
    output :: [4]UInt8 = (9, 9, 9, 9)
    source :: Source = (.bytes = view(.array = &input), .position = 0, .calls = 0)
    sink :: Sink = (.bytes = view(.array = $&output), .position = 0, .stalled = false)
    scratch :: [2]UInt8 = (0, 0)
    if copy_stream(.reader = $&source, .writer = $&sink, .buffer = view(.array = $&scratch))! != 4 {
        abort
    }
    if output[0] != 65 or output[1] != 0 or output[2] != 66 or output[3] != 10 { abort }
    source.position = 0
    read_exact(.self = $&source, .buffer = view(.array = $&output))!
    match read_exact(.self = $&source, .buffer = view(.array = $&scratch)) {
        ..ok _ { abort } ..error error { if error.reason != ..unexpected_eof { abort } }
    }
    source.position = 0
    first ::= read_until(.self = $&source, .buffer = view(.array = $&scratch), .delimiter = 10)!
    if first.count != 2 or first.termination != ..limit or source.position != 2 { abort }
    last ::= read_until(.self = $&source, .buffer = view(.array = $&scratch), .delimiter = 10)!
    if last.count != 1 or last.termination != ..delimiter { abort }
    sink.stalled = true
    match write_all(.self = $&sink, .buffer = view(.array = &input)) {
        ..ok _ { abort } ..error _ {}
    }
    virtual ::= to_virtual#(.abstract: BlockReader)(.value = $&source)
    match read_exact(.self = $&virtual, .buffer = view(.array = $&scratch)) {
        ..ok _ { abort } ..error _ {}
    }
}
