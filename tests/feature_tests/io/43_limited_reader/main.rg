main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    bytes :: [3]UInt8 = (10, 20, 30)
    reader ::= ByteReader(.bytes = view(.self = &bytes))
    {
        limited ::= LimitedReader#(.t: ByteReader)(.source = $&reader, .limit = 2)
        buffer :: [3]UInt8 = (99, 99, 99)
        count ::= unwrap_or_abort(
            .value = BlockReader#(
            ).read_block(.self = $&limited, .buffer = view(.self = $&buffer))
        )
        if count != 2 { abort }
        if buffer[0] != 10 or buffer[1] != 20 or buffer[2] != 99 { abort }
        if remaining(.self = &limited).count != 0 { abort }
        if [
            unwrap_or_abort(
                .value = BlockReader#(
                ).read_block(.self = $&limited, .buffer = view(.self = $&buffer))
            )
            != 0
        ] { abort }
    }
    if position(.self = &reader).count != 2 { abort }
    match unwrap_or_abort(.value = Reader#().read_byte(.self = $&reader)) {
        ..end { abort }
        ..ok byte { if byte != 30 { abort } }
    }
    other ::= ByteReader(.bytes = view(.self = &bytes))
    scratch :: [1]UInt8 = (99)
    zero ::= LimitedReader#(.t: ByteReader)(.source = $&other, .limit = 0)
    if [
        unwrap_or_abort(
            .value = BlockReader#(
            ).read_block(.self = $&zero, .buffer = view(.self = $&scratch))
        )
        != 0
    ] {
        abort
    }
}
