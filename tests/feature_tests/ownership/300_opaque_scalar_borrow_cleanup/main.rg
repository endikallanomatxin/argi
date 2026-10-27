Borrowing := (.counter: $&Int32)

implement Deinit#(Borrowing) (
    .deinit = (.self: $&Borrowing) -> () {
        self&.counter&= self&.counter&+ 1
    }
)

exercise := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .counter: $&Int32, .allocator: $&AllocatorType
) -> () {
    assume allocator
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: Borrowing)(.capacity = 1))
    element ::= Borrowing(.counter = counter)
    pushed ::= push(.self = $&array, .value = ~element)
    if is(.value = pushed, .variant = ..error) { abort }
}

forward := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .counter: $&Int32, .allocator: $&AllocatorType
) -> () {
    exercise(.counter = counter, .allocator = allocator)
}

main := (.system: System) -> (.status_code: Int32) {
    counter :: Int32 = 0
    {
        assume allocator ::= system.page_allocator
        array ::= unwrap_or_abort(.value = DynamicArray#(.t: Borrowing)(.capacity = 1))
        element ::= Borrowing(.counter = $&counter)
        pushed ::= push(.self = $&array, .value = ~element)
        if is(.value = pushed, .variant = ..error) { abort }
    }
    if counter != 1 {
        status_code = 1
        return
    }
    exercise(.counter = $&counter, .allocator = system.page_allocator)
    if counter != 2 {
        status_code = 2
        return
    }
    forward(.counter = $&counter, .allocator = system.page_allocator)
    counter = counter + 1
    status_code = counter - 4
}
