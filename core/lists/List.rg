-- Collection capabilities use named operations. Bracket indexing belongs to
-- native arrays and cannot be supplied by a library type.
Indexable#(.t: Type) : Abstract = (
    length(.self: &Self) -> (.count: UIntNative)
    get_ro_ref(.self: &Self, .index: UIntNative) -> (.result: Errable#(.t: &t, .reasons: (..out_of_bounds)))
)

IndexableMutable#(.t: Type) : Abstract = (
    length(.self: &Self) -> (.count: UIntNative)
    get_ro_ref(.self: &Self, .index: UIntNative) -> (.result: Errable#(.t: &t, .reasons: (..out_of_bounds)))
    get_rw_ref(.self: $&Self, .index: UIntNative) -> (.result: Errable#(.t: $&t, .reasons: (..out_of_bounds)))
)

-- Value reads are an additional capability of collections whose elements
-- can be copied implicitly. Mutable collections decide whether replacing an
-- element needs an allocator to destroy the previous value.
IndexableValue#(.t: Type: ImplicitlyCopyable) : Abstract = (
    get(.self: &Self, .index: UIntNative) -> (.result: Errable#(.t: t, .reasons: (..out_of_bounds)))
)

Resizable#(.t: Type) : Abstract = (
    push(.self: $&Self, .value: t, .allocator: $&Allocator) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory)))
    pop(.self: $&Self) -> (.result: Errable#(.t: t, .reasons: (..empty)))
    insert(.self: $&Self, .i: UIntNative, .value: t, .allocator: $&Allocator) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory, ..out_of_bounds)))
    remove(.self: $&Self, .i: UIntNative) -> (.result: Errable#(.t: t, .reasons: (..out_of_bounds)))
)
