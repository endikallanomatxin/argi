join := (
    .left: &StringView, .right: &StringView, .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(String, (..out_of_memory))) {

    assume allocator
    result = ~[left + right]
}

main := (.system: System) -> (.status_code: Int32 = 0) {

    storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&storage
    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)
    assume allocator := $&virtual_allocator
    left ::= "hello"
    right ::= " world"
    first ::= unwrap_or_abort(.value = &left + &right)
    second ::= unwrap_or_abort(.value = join(&left, &right, .allocator = allocator))
    first_view ::= view(&first)
    second_view ::= view(&second)
    if first_view != "hello world" or second_view != "hello world" { status_code = 1 }
}
