-- Append-only indices borrow a stable domain marker, never a resizable buffer.
-- Kind separates entity categories; membership is checked at runtime because
-- temporal dependency alone does not prove that two owners are identical.
Index := #(.Kind: Type) (._owner: &UInt8, ._offset: UIntNative)

implement#(.Kind: Type) ImplicitlyCopyable#(Index#(Kind)) ()

IndexDomain := (._marker: DynamicArray#(UInt8))

IndexDomainInitArgs := #(.Provider: Type: Allocator) (.allocator: $&Provider)

implement#(.Provider: Type: Allocator) Init#(IndexDomain, IndexDomainInitArgs#(Provider)) (
    .Result : Type = Errable#(IndexDomain, (..out_of_memory))
    .init   = IndexDomainInitArgs#(Provider) -> (.result: Result) {
        marker ::= DynamicArray#(UInt8)(.allocator = allocator, .capacity = 1)!
        push($&marker, .value = 0, .allocator = allocator)!
        result = ..ok(._marker = ~marker)
    }
)

bind_index := #(.Kind: Type) (.domain: &IndexDomain, .offset: UIntNative) -> (
    .value : Index#(Kind)
) {
    owner ::= unwrap_or_abort(.value = get_reference(&domain&._marker, .index = 0)).result
    value = (._owner = owner, ._offset = offset)
}

resolve_index := #(.Kind: Type) (.domain: &IndexDomain, .index: Index#(Kind)) -> (
    .result : Errable#(UIntNative, (..wrong_domain))
) {
    owner ::= unwrap_or_abort(.value = get_reference(&domain&._marker, .index = 0)).result
    actual ::= owner | convert#(.to: UIntNative)(_)
    expected ::= index._owner | convert#(.to: UIntNative)(_)
    if actual != expected {
        result = ..error(.reason = ..wrong_domain)
        return
    }
    result = ..ok index._offset
}
