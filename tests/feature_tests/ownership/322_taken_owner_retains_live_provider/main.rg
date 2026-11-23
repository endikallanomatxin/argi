-- Positive control. The caller keeps the provider alive through cleanup.
take := #(.T: Type) (.slot: $&?T) -> (.result: T) {
    previous ::= ~slot&
    slot& = ..none
    match previous {
        ..none { abort }
        ..some ~payload { result = ~payload.value }
    }
}
make := (.allocator: Virtual#(Allocator)) -> (.result: String) {
    text ::= unwrap_or_abort(String(.length = 1, .allocator = allocator))
    _ = unwrap_or_abort(set_ascii(.self = $&text, .index = 0, .byte = 65))
    slot :: ?String = ..some(.value = ~text)
    owner ::= take#(String)($&slot)
    result = ~owner
}
main := (.system: System) -> () {
    storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    owner ::= make(Virtual#(Allocator)($&storage))
    if unwrap_or_abort(bytes_get(.view = &owner, .index = 0)) != 65 { abort }
}
