read_count := #(.T: Type: BlockReader#(T)) (
    .reader: $&T, .buffer: MutableArrayView#(.t: UInt8), .error_tracer: $&Virtual#(ErrorTracer)
) -> (.count: UIntNative) {
    assume error_tracer
    count = unwrap_or_abort(.value = BlockReader#().read_block(reader, .buffer = buffer))
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    bytes: [2]UInt8 = (42, 7)
    scratch :: [1]UInt8 = (0)
    reader ::= ByteReader(.bytes = view(&bytes))
    if read_count($&reader, .buffer = view($&scratch)).count != 1 { abort }
    if scratch[0] != 42 { abort }
    erased ::= to_virtual#(.contract: BlockReader)(.value = $&reader)
    if read_count($&erased, .buffer = view($&scratch)).count != 1 { abort }
    if scratch[0] != 7 { abort }
}
