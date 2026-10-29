-- A fixed-size owning bit set. Mutable borrowed views retain the backing
-- dynamic array's storage and shape, and therefore cannot outlive cleanup.
BitSet := (._storage: DynamicArray#(.t: UInt8), ._count: UIntNative)

BitSetInitArgs: Type = #(.Provider: Type: Allocator) (
    .count     : UIntNative,
    .allocator : $&Provider
    ,
    .error_tracer : $&Virtual#(ErrorTracer)
)

implement#(.Provider: Type: Allocator) Init#(BitSet, BitSetInitArgs#(Provider)) (
    .Result : Type = Errable#(BitSet, (..out_of_memory))

    .init = BitSetInitArgs#(Provider) -> (.result: Result) {
        assume error_tracer

        _init_count ::= count
        _init_allocator ::= allocator

        assume allocator := _init_allocator
        needed ::= _init_count / 8

        if _init_count % 8 != 0 { needed = needed + 1 }
        storage ::= DynamicArray#(.t: UInt8)(.allocator = _init_allocator, .capacity = needed)!
        index :: UIntNative = 0

        while index < needed {
            push_assume_capacity($&storage, .value = 0)
            index = index + 1
        }

        result = ..ok(._storage = ~storage, ._count = _init_count)
    }
)

implement Deinit#(BitSet) (
    .deinit = (.self: $&BitSet) -> () {
        deinit(.self = $&self&._storage)
    }
)

_collection_length_owned_bit_set := (.self: &BitSet) -> (.count: UIntNative) {
    count = self&._count
}

implement CollectionLength#(BitSet) (
    .measure_length = _collection_length_owned_bit_set
)

implement Viewable#($&BitSet) (
    .Result    : Type = BitSetView
    .make_view = (.self: $&BitSet) -> (.view: BitSetView) {
        view = (._bytes = view($&self&._storage), ._count = self&._count)
    }
)

_bit_query_BitSet := (
    .self: &BitSet, .index: UIntNative, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Bool, (..out_of_bounds))) {
    assume error_tracer

    if index >= self&._count {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    byte ::= unwrap_or_abort(.value = get_reference(&self&._storage, .index = index / 8))
    mask ::= _bit_set_mask(.index = index).mask

    result = ..ok byte&/ mask % 2 != 0
}

_bit_write_BitSet := (
    .self         : $&BitSet,
    .index        : UIntNative,
    .value        : Bool                    = true,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Void, (..out_of_bounds))) {
    assume error_tracer

    borrowed_view ::= view(self).view

    result = set_bit($&borrowed_view, .index = index, .value = value)
}

_bit_count_BitSet := (.self: &BitSet) -> (.count: UIntNative) {
    count = _bit_set_count(.bytes = view(.self = &self&._storage), .extent = self&._count).count
}

implement BitSetAccess#(BitSet) (
    .read_bit   = _bit_query_BitSet
    .write_bit  = _bit_write_BitSet
    .population = _bit_count_BitSet
)
