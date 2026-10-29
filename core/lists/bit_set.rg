-- A bounded bit set borrows initialized bytes. Bit zero is the low bit of
-- byte zero. Construction clears only the bytes needed for the requested bits.
BitSetView := (._bytes: MutableArrayView#(.t: UInt8), ._count: UIntNative)

BitSetViewInitArgs: Type = (
    .bytes        : MutableArrayView#(.t: UInt8),
    .count        : UIntNative,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
)

implement Init#(BitSetView, BitSetViewInitArgs) (
    .Result : Type = Errable#(BitSetView, (..out_of_bounds))

    .init = BitSetViewInitArgs -> (.result: Result) {
        assume error_tracer

        _init_bytes ::= bytes
        _init_count ::= count

        needed ::= _init_count / 8

        if _init_count % 8 != 0 { needed = needed + 1 }
        if needed > length(&_init_bytes).count {
            result = ..error(.reason = ..out_of_bounds)
            return
        }

        index :: UIntNative = 0

        while index < needed {
            target ::= unwrap_or_abort(
                .value = get_mutable_reference($&_init_bytes, .index = index)
            )
            target&= 0
            index = index + 1
        }

        result = ..ok(._bytes = _init_bytes, ._count = _init_count)
    }
)

_collection_length_bit_set := (.self: &BitSetView) -> (.count: UIntNative) {
    count = self&._count
}

implement CollectionLength#(BitSetView) (
    .measure_length = _collection_length_bit_set
)

_bit_set_mask := (.index: UIntNative) -> (.mask: UInt8 = 1) {
    offset ::= index % 8

    while offset > 0 {
        mask = mask * 2
        offset = offset - 1
    }
}

_bit_query_BitSetView := (
    .self         : &BitSetView,
    .index        : UIntNative,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Bool, (..out_of_bounds))) {
    assume error_tracer

    if index >= self&._count {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    byte ::= unwrap_or_abort(.value = get_reference(&self&._bytes, .index = index / 8))
    mask ::= _bit_set_mask(.index = index).mask

    result = ..ok byte&/ mask % 2 != 0
}

_bit_write_BitSetView := (
    .self         : $&BitSetView,
    .index        : UIntNative,
    .value        : Bool          = true,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Void, (..out_of_bounds)) = ..ok Void()) {
    assume error_tracer

    present ::= contains_bit(self, .index = index)!

    if present == value { return }
    byte ::= unwrap_or_abort(.value = get_mutable_reference($&self&._bytes, .index = index / 8))
    mask ::= _bit_set_mask(.index = index).mask

    if value { byte&= byte&+ mask } else { byte&= byte&- mask }
}

_bit_set_count := (.bytes: ArrayView#(.t: UInt8), .extent: UIntNative) -> (
    .count : UIntNative = 0
) {
    full ::= extent / 8
    index :: UIntNative = 0

    while index < full {
        byte ::= unwrap_or_abort(.value = get_reference(&bytes, .index = index))
        count = count + count_ones#(.t: UInt8)(.value = byte&).count
        index = index + 1
    }

    remaining ::= extent % 8

    if remaining == 0 { return }
    tail ::= unwrap_or_abort(.value = get_reference(&bytes, .index = full))&

    while remaining > 0 {
        if tail % 2 != 0 { count = count + 1 }
        tail = tail / 2
        remaining = remaining - 1
    }
}

_bit_count_BitSetView := (.self: &BitSetView) -> (.count: UIntNative) {
    count = _bit_set_count(
        .bytes = as_readonly(&self&._bytes).view, .extent = self&._count
    ).count
}

implement BitSetAccess#(BitSetView) (
    .read_bit   = _bit_query_BitSetView
    .write_bit  = _bit_write_BitSetView
    .population = _bit_count_BitSetView
)
