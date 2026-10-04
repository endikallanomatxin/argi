-- Bytes are decoded explicitly, independently of alignment and target layout.
ByteOrder: Type = (..little, ..big)

ByteOrder implements ImplicitlyCopyable

_binary_range(.length: UIntNative, .offset: UIntNative, .width: UIntNative) -> (.ok: Bool) := {
    ok = false
    if offset <= length { ok = width <= length - offset }
}

read_uint16(
        .bytes  : ArrayViewRO#(.t: UInt8),
        .offset : UIntNative               = 0,
        .order  : ByteOrder
    ) -> (
        .result : Errable#(.t: UInt16, .reasons: (..out_of_bounds))
    ) := {
    if [
        _binary_range(.length = length(.self = &bytes).count, .offset = offset, .width = 2).ok
        == false
    ] {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    value :: UInt16 = 0
    last: UIntNative = 1
    index :: UIntNative = 0
    while index < 2 {
        position :: UIntNative = index
        if order == ..little { position = last - index }
        byte ::= get_ro_ref(.self = &bytes, .index = offset + position)!
        value = value * 256 + UInt16(.value = byte&)
        index = index + 1
    }
    result = ..ok value
}

write_uint16(
        .bytes  : ArrayView#(.t: UInt8),
        .offset : UIntNative             = 0,
        .value  : UInt16,
        .order  : ByteOrder
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..out_of_bounds))
    ) := {
    -- Prove the whole range before any destination byte changes.
    if [
        _binary_range(.length = length(.self = &bytes).count, .offset = offset, .width = 2).ok
        == false
    ] {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    remaining :: UInt16 = value
    last: UIntNative = 1
    index :: UIntNative = 0
    while index < 2 {
        position :: UIntNative = index
        if order == ..big { position = last - index }
        byte ::= get_rw_ref(.self = $&bytes, .index = offset + position)!
        byte&= unwrap_or_abort(.value = UInt8(.value = remaining % 256))
        remaining = remaining / 256
        index = index + 1
    }
    result = ..ok Void()
}

read_uint32(
        .bytes  : ArrayViewRO#(.t: UInt8),
        .offset : UIntNative               = 0,
        .order  : ByteOrder
    ) -> (
        .result : Errable#(.t: UInt32, .reasons: (..out_of_bounds))
    ) := {
    if [
        _binary_range(.length = length(.self = &bytes).count, .offset = offset, .width = 4).ok
        == false
    ] {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    value :: UInt32 = 0
    last: UIntNative = 3
    index :: UIntNative = 0
    while index < 4 {
        position :: UIntNative = index
        if order == ..little { position = last - index }
        byte ::= get_ro_ref(.self = &bytes, .index = offset + position)!
        value = value * 256 + UInt32(.value = byte&)
        index = index + 1
    }
    result = ..ok value
}

write_uint32(
        .bytes  : ArrayView#(.t: UInt8),
        .offset : UIntNative             = 0,
        .value  : UInt32,
        .order  : ByteOrder
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..out_of_bounds))
    ) := {
    -- Prove the whole range before any destination byte changes.
    if [
        _binary_range(.length = length(.self = &bytes).count, .offset = offset, .width = 4).ok
        == false
    ] {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    remaining :: UInt32 = value
    last: UIntNative = 3
    index :: UIntNative = 0
    while index < 4 {
        position :: UIntNative = index
        if order == ..big { position = last - index }
        byte ::= get_rw_ref(.self = $&bytes, .index = offset + position)!
        byte&= unwrap_or_abort(.value = UInt8(.value = remaining % 256))
        remaining = remaining / 256
        index = index + 1
    }
    result = ..ok Void()
}

read_uint64(
        .bytes  : ArrayViewRO#(.t: UInt8),
        .offset : UIntNative               = 0,
        .order  : ByteOrder
    ) -> (
        .result : Errable#(.t: UInt64, .reasons: (..out_of_bounds))
    ) := {
    if [
        _binary_range(.length = length(.self = &bytes).count, .offset = offset, .width = 8).ok
        == false
    ] {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    value :: UInt64 = 0
    last: UIntNative = 7
    index :: UIntNative = 0
    while index < 8 {
        position :: UIntNative = index
        if order == ..little { position = last - index }
        byte ::= get_ro_ref(.self = &bytes, .index = offset + position)!
        value = value * 256 + UInt64(.value = byte&)
        index = index + 1
    }
    result = ..ok value
}

write_uint64(
        .bytes  : ArrayView#(.t: UInt8),
        .offset : UIntNative             = 0,
        .value  : UInt64,
        .order  : ByteOrder
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..out_of_bounds))
    ) := {
    -- Prove the whole range before any destination byte changes.
    if [
        _binary_range(.length = length(.self = &bytes).count, .offset = offset, .width = 8).ok
        == false
    ] {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    remaining :: UInt64 = value
    last: UIntNative = 7
    index :: UIntNative = 0
    while index < 8 {
        position :: UIntNative = index
        if order == ..big { position = last - index }
        byte ::= get_rw_ref(.self = $&bytes, .index = offset + position)!
        byte&= unwrap_or_abort(.value = UInt8(.value = remaining % 256))
        remaining = remaining / 256
        index = index + 1
    }
    result = ..ok Void()
}
