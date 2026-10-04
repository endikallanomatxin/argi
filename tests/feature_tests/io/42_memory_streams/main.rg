main() -> (.status_code: Int32 = 0) := {
    source :: [4]UInt8 = (1, 0, 255, 7)
    reader ::= ByteReader(.bytes = view(.array = &source))
    destination :: [3]UInt8 = (9, 9, 9)
    writer ::= ByteWriter(.bytes = view(.array = $&destination))
    scratch :: [2]UInt8 = (0, 0)
    copied ::= unwrap_or_abort(
        .value = copy_stream_limited(
            .reader = $&reader
            .writer = $&writer
            .buffer = view(.array = $&scratch)
            .limit  = 3
        )
    )
    if copied.count != 3 { abort }
    if position(.self = &reader).count != 3 { abort }
    if position(.self = &writer).count != 3 { abort }
    match write_byte(.self = $&writer, .byte = 99) { ..ok _ { abort } ..error _ {} }
    if position(.self = &writer).count != 3 { abort }
    match unwrap_or_abort(.value = read_byte(.self = $&reader)) {
        ..end { abort }
        ..ok byte { if byte != 7 { abort } }
    }
    match unwrap_or_abort(.value = read_byte(.self = $&reader)) { ..end {} ..ok _ { abort } }
    unwrap_or_abort(.value = flush(.self = $&writer))
    another :: [2]UInt8 = (0, 0)
    partial ::= ByteWriter(.bytes = view(.array = $&another))
    if [
        unwrap_or_abort(.value = write_block(.self = $&partial, .buffer = view(.array = &source)))
        != 2
    ] { abort }
    if position(.self = &partial).count != 2 { abort }
    empty ::= array_view_ro#(.t: UInt8)()
    if unwrap_or_abort(.value = write_block(.self = $&partial, .buffer = empty)) != 0 { abort }
    match write_block(.self = $&partial, .buffer = view(.array = &source)) {
        ..ok _ { abort } ..error _ {}
    }

}
