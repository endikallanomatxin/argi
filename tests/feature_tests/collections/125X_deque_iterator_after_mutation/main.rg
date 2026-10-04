main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    queue ::= Deque#(.t: Int32)(.capacity = 8)!
    push_back(.self = $&queue, .value = 1)!
    iterator ::= to_iterator(.value = &queue).iterator
    push_front(.self = $&queue, .value = 2)!
    _ ::= next(.self = $&iterator)
}
