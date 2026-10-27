main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    queue ::= Deque#(.t: Int32)(.capacity = 2)!!!
    push_back(.self = $&queue, .value = 1)!!!
    iterator ::= to_reference_iterator(.value = &queue).iterator
    reference ::= next(.self = $&iterator).value
    _ ::= pop_front(.self = $&queue)!!!
    _ ::= reference&
    status_code = 0
}
