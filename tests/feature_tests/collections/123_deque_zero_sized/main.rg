Empty: Type = ()

main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    queue ::= Deque#(.t: Empty)(.capacity = 0)!
    index :: UIntNative = 0
    while index < 32 {
        push_front(.self = $&queue, .value = Empty())!
        index = index + 1
    }
    if length(.self = &queue).count != 32 { abort }
    index = 0
    while index < 32 {
        _ = pop_back(.self = $&queue)!
        index = index + 1
    }
}
