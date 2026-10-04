main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    queue ::= Deque#(.t: Int32)(.capacity = 2)!
    push_back(.self = $&queue, .value = 1)!
    iterator ::= to_ro_pointer_iterator(.value = &queue).iterator
    reference ::= next(.self = $&iterator).value
    _ ::= pop_front(.self = $&queue)!
    _ ::= reference&
}
