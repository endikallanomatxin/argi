drops :: Int32 = 0

record_drop := () -> () { drops = drops + 1 }

Owner := (.value: Int32)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { record_drop() }
)

partial := (.allocator: $&PageAllocator) -> (
    .result: Errable#(DynamicArray#(Owner), (..out_of_memory, ..copy_failed))
) {
    assume allocator
    values ::= DynamicArray#(Owner)(.capacity = 1)!
    item ::= Owner(42)
    push_assume_capacity#(Owner)($&values, .value = ~item)
    result = ..error(.reason = ..copy_failed)
}

nested := (.allocator: $&PageAllocator) -> () {
    assume allocator
    inner ::= unwrap_or_abort(DynamicArray#(Owner)(.capacity = 2))
    first ::= Owner(1)
    second ::= Owner(2)
    push_assume_capacity#(Owner)($&inner, .value = ~first)
    push_assume_capacity#(Owner)($&inner, .value = ~second)
    outer ::= unwrap_or_abort(DynamicArray#(DynamicArray#(Owner))(.capacity = 1))
    push_assume_capacity#(DynamicArray#(Owner))($&outer, .value = ~inner)
}

explicit := (.allocator: $&PageAllocator) -> () {
    assume allocator
    values ::= unwrap_or_abort(DynamicArray#(Owner)(.capacity = 1))
    item ::= Owner(7)
    push_assume_capacity#(Owner)($&values, .value = ~item)
    Deinit#(DynamicArray#(Owner)).deinit(.self = $&values)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume allocator := system.page_allocator
    match partial(allocator) {
        ..ok ~value { abort }
        ..error error {
            if is(.value = error.reason, .variant = ..copy_failed) {} else { abort }
        }
    }
    if drops != 1 { abort }
    nested(allocator)
    if drops != 3 { abort }
    explicit(allocator)
    if drops != 4 { abort }
}
