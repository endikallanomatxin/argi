-- Collection capabilities use named operations. Bracket indexing belongs to
-- native arrays and cannot be supplied by a library type.
Indexable: Contract = (
    .t: Type

    length(.self: &Self) -> (.count: UIntNative)
    get_ro_ref(.self: &Self, .index: UIntNative) -> (
        .result : Errable#(&t, (..out_of_bounds))
    )
)

-- Logical elements are independently replaceable: writing an indexed
-- reference changes that position without replacing other logical elements
-- or resizing the collection.
IndexableMutable: Contract = (
    .t: Type

    length(.self: &Self) -> (.count: UIntNative)
    get_ro_ref(.self: &Self, .index: UIntNative) -> (
        .result : Errable#(&t, (..out_of_bounds))
    )
    get_rw_ref(.self: $&Self, .index: UIntNative) -> (
        .result : Errable#($&t, (..out_of_bounds))
    )
)

-- Value reads are an additional capability of collections whose elements
-- can be copied implicitly. Mutable collections decide whether replacing an
-- element needs an allocator to destroy the previous value.
IndexableValue: Contract = (
    .t: Type: ImplicitlyCopyable

    get(.self: &Self, .index: UIntNative) -> (
        .result : Errable#(t, (..out_of_bounds))
    )
)

Resizable: Contract = (
    .t: Type

    push(.self: $&Self, .value: t, .allocator: $&Allocator) -> (
        .result : Errable#(Void, (..out_of_memory))
    )
    pop(.self: $&Self) -> (.result: Errable#(t, (..empty)))
    insert(.self: $&Self, .i: UIntNative, .value: t, .allocator: $&Allocator) -> (
        .result : Errable#(Void, (..out_of_memory, ..out_of_bounds))
    )
    remove(.self: $&Self, .i: UIntNative) -> (
        .result : Errable#(t, (..out_of_bounds))
    )
)
