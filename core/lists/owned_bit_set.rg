-- A fixed-size owning bit set. Mutable borrowed views retain the backing
-- dynamic array's storage and shape, and therefore cannot outlive cleanup.
BitSet := (._storage: DynamicArray<.t: UInt8>, ._count: UIntNative)

implement<.Provider: Type: Allocator> Init<
    BitSet, (.count: UIntNative, .allocator: $&Provider = reach allocator)
> (
    .Result : Type = Errable<BitSet, (..out_of_memory)>
    .init   = (.args: (.count: UIntNative, .allocator: $&Provider = reach allocator)) -> (
        .result : Result
    ) {
        count ::= args.count
        allocator ::= args.allocator

        assume allocator
        needed ::= count / 8

        if count % 8 != 0 { needed = needed + 1 }
        storage ::= DynamicArray<.t: UInt8>(.allocator = allocator, .capacity = needed)!
        index :: UIntNative = 0

        while index < needed {
            push_assume_capacity($&storage, .value = 0)
            index = index + 1
        }

        result = ..ok(._storage = ~storage, ._count = count)
    }
)

implement Deinit<BitSet> (
    .deinit = (.self: $&BitSet) -> () {
        deinit(.self = $&self&._storage)
    }
)

_collection_length_owned_bit_set := (.self: &BitSet) -> (.count: UIntNative) {
    count = self&._count
}

implement CollectionLength<BitSet> (
    .measure_length = _collection_length_owned_bit_set
)

implement Viewable<$&BitSet> (
    .Result    : Type = BitSetView
    .make_view = (.self: $&BitSet) -> (.view: BitSetView) {
        view = (._bytes = view($&self&._storage), ._count = self&._count)
    }
)

_bit_query_BitSet := (.self: &BitSet, .index: UIntNative) -> (
    .result: Errable<Bool, (..out_of_bounds)>
) {
    if index >= self&._count {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    byte ::= unwrap_or_abort(.value = get_reference(&self&._storage, .index = index / 8))
    mask ::= _bit_set_mask(.index = index).mask

    result = ..ok byte&/ mask % 2 != 0
}

_bit_write_BitSet := (.self: $&BitSet, .index: UIntNative, .value: Bool = true) -> (
    .result: Errable<Void, (..out_of_bounds)>
) {
    borrowed_view ::= view(self).view

    result = set_bit($&borrowed_view, .index = index, .value = value)
}

_bit_count_BitSet := (.self: &BitSet) -> (.count: UIntNative) {
    count = _bit_set_count(.bytes = view(.self = &self&._storage), .extent = self&._count).count
}

implement BitSetAccess<BitSet> (
    .read_bit   = _bit_query_BitSet
    .write_bit  = _bit_write_BitSet
    .population = _bit_count_BitSet
)
