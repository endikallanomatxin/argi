run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    queue ::= Deque#(.t: Int32)(.capacity = 2)!
    push_back(.self = $&queue, .value = 1)!
    iterator ::= to_reference_iterator(.value = &queue).iterator
    reference ::= next(.self = $&iterator).value
    _ ::= pop_front(.self = $&queue)!
    _ ::= reference&
}

main#(.WriterType: Type: Writer#(WriterType))(
    .system: System, .writer: $&WriterType = reach writer
) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
