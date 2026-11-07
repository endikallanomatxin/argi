test storage_index_domain_membership := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    first ::= IndexDomain()!
    second ::= IndexDomain()!
    id ::= bind_index#(UIntNative)(.domain = &first, .offset = 42).value
    testing.expect([resolve_index(.domain = &first, .index = id)!] == 42)!
    rejected ::= false
    match resolve_index(.domain = &second, .index = id) {
        ..ok _ {}
        ..error error { rejected = error.reason == ..wrong_domain }
    }
    testing.expect(rejected)!
}

test storage_index_domain_transfer := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    original ::= IndexDomain()!
    id ::= bind_index#(UIntNative)(.domain = &original, .offset = 7).value
    transferred ::= ~original
    [
        testing.expect([[resolve_index(.domain = &transferred, .index = id)!] == 7])!
    ]
}

test storage_index_survives_unrelated_growth := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)

    domain ::= IndexDomain()!
    id ::= bind_index#(UIntNative)(.domain = &domain, .offset = 0).value
    values ::= DynamicArray#(UIntNative)()!
    i :: UIntNative = 0
    while i < 257 {
        [push($&values, .value = i, .allocator = allocator)!]
        i = i + 1
    }
    offset ::= resolve_index(.domain = &domain, .index = id)!
    testing.expect([get(&values, .index = offset)!] == 0)!
}
