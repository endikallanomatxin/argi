-- Compile-only negative design case. The returned owner retains a local provider.
take := #(.T: Type) (.slot: $&?T) -> (.result: T) {
    previous ::= ~slot&
    slot& = ..none
    match previous {
        ..none { abort }
        ..some ~payload { result = ~payload.value }
    }
}
escape := (.system: System) -> (.result: String) {
    storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator ::= Virtual#(Allocator)($&storage)
    text ::= unwrap_or_abort(String(.length = 1, .allocator = allocator))
    _ = unwrap_or_abort(set_ascii(.self = $&text, .index = 0, .byte = 65))
    slot :: ?String = ..some(.value = ~text)
    owner ::= take#(String)($&slot)
    result = ~owner
}
main := (.system: System) -> () {
    owner ::= escape(system)
    if unwrap_or_abort(bytes_get(.view = &owner, .index = 0)) != 65 { abort }
}
