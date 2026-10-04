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

main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    input :: [4]UInt8 = (65, 0, 66, 10)
    output :: [4]UInt8 = (9, 9, 9, 9)
    scratch :: [3]UInt8 = (7, 7, 7)
    source :: Source = (.bytes = view(.array = &input), .position = 0, .calls = 0)
    sink :: Sink = (.bytes = view(.array = $&output), .position = 0, .stalled = false)
    first ::= copy_stream_limited(
        .reader = $&source
        .writer = $&sink
        .buffer = view(.array = $&scratch)
        .limit  = 2
    )!
    if [
        first.count != 2
        or first.termination != ..limit
        or source.position != 2
        or sink.position != 2
    ] { abort }
    if output[0] != 65 or output[1] != 0 or output[2] != 9 { abort }
    last ::= copy_stream_limited(
        .reader = $&source
        .writer = $&sink
        .buffer = view(.array = $&scratch)
        .limit  = 9
    )!
    if last.count != 2 or last.termination != ..end { abort }
    source.position = 0
    sink.position = 0
    source_virtual ::= to_virtual#(.abstract: BlockReader)(.value = $&source)
    sink_virtual ::= to_virtual#(.abstract: BlockWriter)(.value = $&sink)
    copied ::= copy_stream_limited(
        .reader = $&source_virtual
        .writer = $&sink_virtual
        .buffer = view(.array = $&scratch)
        .limit  = 4
    )!
    if copied.count != 4 or copied.termination != ..limit or source.calls != 9 { abort }
    vacant :: [0]UInt8 = ()
    empty ::= view(.array = $&vacant)
    calls ::= source.calls
    zero ::= copy_stream_limited(.reader = $&source, .writer = $&sink, .buffer = empty, .limit = 0)!
    if zero.count != 0 or zero.termination != ..limit or source.calls != calls { abort }
    source.position = 0
    owned ::= read_all_limited(
        .self      = $&source
        .buffer    = view(.array = $&scratch)
        .limit     = 4
        .allocator = allocator
    )!
    if owned.length != 4 or capacity(.self = &owned).value > 4 { abort }
    if [
        bytes_get(.string = &owned, .index = 1).byte != 0
        or bytes_get(.string = &owned, .index = 3).byte != 10
    ] { abort }
    source.position = 0
    other ::= read_all_limited(
        .self      = $&source_virtual
        .buffer    = view(.array = $&scratch)
        .limit     = 8
        .allocator = allocator
    )!
    if other.length != 4 or capacity(.self = &other).value > 8 { abort }
    source.position = 0
    match read_all_limited(
        .self      = $&source
        .buffer    = view(.array = $&scratch)
        .limit     = 2
        .allocator = allocator
    ) {
        ..ok ~owner {
            deinit(.self = $&owner, .allocator = allocator)
            abort
        }
        ..error error { if error.reason != ..size_limit_exceeded { abort } }
    }
    if source.position != 3 { abort }
    source.position = 0
    match read_all_limited(
        .self      = $&source
        .buffer    = view(.array = $&scratch)
        .limit     = 0
        .allocator = allocator
    ) {
        ..ok ~owner {
            deinit(.self = $&owner, .allocator = allocator)
            abort
        }
        ..error error { if error.reason != ..size_limit_exceeded { abort } }
    }
    if source.position != 1 { abort }
    source.position = 4
    nothing ::= read_all_limited(
        .self      = $&source
        .buffer    = view(.array = $&scratch)
        .limit     = 0
        .allocator = allocator
    )!
    if nothing.length != 0 { abort }
    calls = source.calls
    match read_all_limited(.self = $&source, .buffer = empty, .limit = 4, .allocator = allocator) {
        ..ok ~owner {
            deinit(.self = $&owner, .allocator = allocator)
            abort
        } ..error error { if error.reason != ..invalid_stream_buffer { abort } }
    }
    if source.calls != calls { abort }
}
