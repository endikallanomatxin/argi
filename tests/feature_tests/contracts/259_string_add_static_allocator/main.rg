join#(.Provider: Type: Allocator) := (.left: &StringView, .right: &StringView, .allocator: $&Provider) -> (.result: Errable#(String, (..out_of_memory))) {
    result = ~[left + right]
}
main := (.system: System) -> (.status_code: Int32 = 0) {
    storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&storage
    left ::= "hello"
    right ::= " world"
    first ::= unwrap_or_abort(.value = &left + &right)
    second ::= unwrap_or_abort(.value = join(&left, &right, .allocator = $&storage))
    first_view ::= as_view(&first)
    second_view ::= as_view(&second)
    if first_view != "hello world" or second_view != "hello world" { status_code = 1 }
}
