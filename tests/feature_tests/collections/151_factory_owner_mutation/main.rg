Owner := (.first: DynamicArray#(UIntNative), .second: DynamicArray#(UIntNative))

make_owner := (.allocator: Virtual#(Allocator)) -> (
    .result : Errable#(Owner, (..out_of_memory))
) {

    first ::= DynamicArray#(UIntNative)(.allocator = allocator)!
    second ::= DynamicArray#(UIntNative)(.allocator = allocator)!
    result = ..ok(.first = ~first, .second = ~second)
}

consume := (.owner: Owner) -> () {}

main := (.system: System) -> (.status_code: Int32) {

    allocator_concrete := $&GeneralPurposeAllocator(system.page_allocator)

    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)

    assume allocator := virtual_allocator
    owner ::= unwrap_or_abort(.value = make_owner()).result
    unwrap_or_abort(.value = push($&owner.second, .value = 1, .allocator = allocator))
    consume(.owner = ~owner)
    status_code = 0
}
