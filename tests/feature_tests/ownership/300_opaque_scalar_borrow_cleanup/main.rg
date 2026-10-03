Borrowing : Type = (.counter: $&Int32)
Borrowing deinit(.self: $&Borrowing) -> () := {
    self&.counter& = self&.counter& + 1
}
exercise(.counter: $&Int32, .allocator: $&Allocator) -> () := {
    assume allocator
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: Borrowing)(.capacity = 1))
    element ::= Borrowing(.counter = counter)
    pushed ::= push#(.t: Borrowing)(.self = $&array, .value = ~element)
    if is(.value = pushed, .variant = ..error) { abort }
}
forward(.counter: $&Int32, .allocator: $&Allocator) -> () := {
    exercise(.counter = counter, .allocator = allocator)
}
main(.system: System) -> (.status_code: Int32) := {
    counter :: Int32 = 0
    {
        assume allocator ::= system.page_allocator
        array ::= unwrap_or_abort(.value = DynamicArray#(.t: Borrowing)(.capacity = 1))
        element ::= Borrowing(.counter = $&counter)
        pushed ::= push#(.t: Borrowing)(.self = $&array, .value = ~element)
        if is(.value = pushed, .variant = ..error) { abort }
    }
    if counter != 1 { status_code = 1 return }
    exercise(.counter = $&counter, .allocator = system.page_allocator)
    if counter != 2 { status_code = 2 return }
    forward(.counter = $&counter, .allocator = system.page_allocator)
    counter = counter + 1
    status_code = counter - 4
}
