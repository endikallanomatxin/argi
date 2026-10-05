-- A bounded bit set borrows initialized bytes. Bit zero is the low bit of
-- byte zero. Construction clears only the bytes needed for the requested bits.
BitSetView: Type = (._bytes: ArrayView#(.t: UInt8), ._count: UIntNative)

BitSetView init(
        .bytes : ArrayView#(.t: UInt8),
        .count : UIntNative
    ) -> (
        .result : Errable#(.t: BitSetView, .reasons: (..out_of_bounds))
    ) := {
    needed ::= count / 8

    if count % 8 != 0 { needed = needed + 1 }
    if needed > length(&bytes).count {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    index :: UIntNative = 0

    while index < needed {
        target ::= unwrap_or_abort(.value = get_rw_ref(.self = $&bytes, .index = index))
        target&= 0
        index = index + 1
    }

    result = ..ok(._bytes = bytes, ._count = count)
}

length(.self: &BitSetView) -> (.count: UIntNative) := { count = self&._count }

_bit_set_mask(.index: UIntNative) -> (.mask: UInt8 = 1) := {
    offset ::= index % 8

    while offset > 0 {
        mask = mask * 2
        offset = offset - 1
    }
}

contains(
        .self  : &BitSetView,
        .index : UIntNative
    ) -> (
        .result : Errable#(.t: Bool, .reasons: (..out_of_bounds))
    ) := {
    if index >= self&._count {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    byte ::= unwrap_or_abort(.value = get_ro_ref(.self = &self&._bytes, .index = index / 8))
    mask ::= _bit_set_mask(.index = index).mask

    result = ..ok byte&/ mask % 2 != 0
}

set(
        .self  : $&BitSetView,
        .index : UIntNative,
        .value : Bool          = true
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..out_of_bounds)) = ..ok Void()
    ) := {
    present ::= contains(.self = self, .index = index)!

    if present == value { return }
    byte ::= unwrap_or_abort(.value = get_rw_ref(.self = $&self&._bytes, .index = index / 8))
    mask ::= _bit_set_mask(.index = index).mask

    if value { byte&= byte&+ mask } else { byte&= byte&- mask }
}

_bit_set_count(.bytes: ArrayViewRO#(.t: UInt8), .extent: UIntNative) -> (.count: UIntNative = 0) := {
    full ::= extent / 8
    index :: UIntNative = 0

    while index < full {
        byte ::= unwrap_or_abort(.value = get_ro_ref(.self = &bytes, .index = index))
        count = count + count_ones#(.t: UInt8)(.value = byte&).count
        index = index + 1
    }

    remaining ::= extent % 8

    if remaining == 0 { return }
    tail ::= unwrap_or_abort(.value = get_ro_ref(.self = &bytes, .index = full))&

    while remaining > 0 {
        if tail % 2 != 0 { count = count + 1 }
        tail = tail / 2
        remaining = remaining - 1
    }
}

count_set(.self: &BitSetView) -> (.count: UIntNative) := {
    count = _bit_set_count(
        .bytes  = as_readonly(.self = &self&._bytes).view
        .extent = self&._count
    ).count
}
