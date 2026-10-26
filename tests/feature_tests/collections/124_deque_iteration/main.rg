main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    queue ::= Deque<.t: Int32>(.capacity = 3)!!!
    push_back(.self = $&queue, .value = 1)!!!
    push_back(.self = $&queue, .value = 2)!!!
    if pop_front(.self = $&queue)!!! != 1 { abort }
    push_back(.self = $&queue, .value = 3)!!!
    push_back(.self = $&queue, .value = 4)!!!
    sum :: Int32 = 0
    for item in queue { sum = sum + item }
    if sum != 9 { abort }
    iterator ::= to_mutable_reference_iterator(.value = $&queue).iterator
    while has_next(.self = &iterator).ok {
        pointer ::= next(.self = $&iterator).value
        pointer&= pointer&+ 10
    }
    readonly ::= to_reference_iterator(.value = &queue).iterator
    sum = 0
    while has_next(.self = &readonly).ok { sum = sum + next(.self = $&readonly).value&}
    if sum != 39 { abort }
    empty ::= Deque<.t: Int32>(.capacity = 8)!!!
    for item in empty { abort }
    status_code = 0
}
