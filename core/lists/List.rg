-- Collection operations retain one identity per capability.
Indexable#(.Collection: Type): Contract = (
    .Item          : Type
    .length        : (.self: &Collection) -> (.count: UIntNative)
    .get_reference : (.self: &Collection, .index: UIntNative) -> (
        .result : Errable#(&Item, (..out_of_bounds))
    )
)

-- Writable indexing reuses the readonly capability without duplicating it.
MutableIndexable#(.Collection: Type): Contract = (
    .Item : Type
    Indexable#(.Collection: Collection, .Item: Item)
    .get_mutable_reference : (.self: $&Collection, .index: UIntNative) -> (
        .result : Errable#($&Item, (..out_of_bounds))
    )
)

IndexableValue#(.Collection: Type): Contract = (
    .Item : Type: ImplicitlyCopyable
    Indexable#(.Collection: Collection, .Item: Item)
    .get : (.self: &Collection, .index: UIntNative) -> (
        .result : Errable#(Item, (..out_of_bounds))
    )
)

-- Removal needs no allocation capability; its identity has one participant.
Removable#(.Collection: Type): Contract = (
    .Item : Type
    MutableIndexable#(.Collection: Collection, .Item: Item)
    .pop    : (.self: $&Collection) -> (.result: Errable#(Item, (..empty)))
    .remove : (.self: $&Collection, .index: UIntNative) -> (
        .result : Errable#(Item, (..out_of_bounds))
    )
)

-- Growth depends on both the collection and the allocation provider. The
-- provider participates in static selection rather than being implicitly erased.
Resizable#(.Collection: Type, .Provider: Type: Allocator#(Provider)): Contract = (
    .Item : Type
    Removable#(.Collection: Collection, .Item: Item)
    .push : (.self: $&Collection, .value: Item, .allocator: $&Provider) -> (
        .result : Errable#(Void, (..out_of_memory))
    )
    .insert : (.self: $&Collection, .index: UIntNative, .value: Item, .allocator: $&Provider) -> (
        .result : Errable#(Void, (..out_of_memory, ..out_of_bounds))
    )
)
