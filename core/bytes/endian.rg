-- Bytes are decoded explicitly, independently of alignment and target layout.
ByteOrder: Type = (..little, ..big)

implement ImplicitlyCopyable#(ByteOrder) ()

_binary_range := (.length: UIntNative, .offset: UIntNative, .width: UIntNative) -> (.ok: Bool) {
    ok = false

    if offset <= length { ok = width <= length - offset }
}

-- One range-checked implementation for the public multi-byte widths.
_read_multibyte_uint_at := #(.Value: Type: UInt) (
    .bytes: ArrayView#(.t: UInt8), .offset: UIntNative = 0, .order: ByteOrder
) -> (.result: Errable#(Value, (..out_of_bounds))) {
    width ::= size_of(.type = Value)
    if [
        _binary_range(.length = length(&bytes).count, .offset = offset, .width = width).ok
        == false
    ] {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    value :: Value = 0
    last ::= width - 1
    index :: UIntNative = 0

    while index < width {
        position :: UIntNative = index
        if order == ..little { position = last - index }
        byte ::= get_reference(&bytes, .index = offset + position)!
        value = value * 256 + byte&| convert#(.to: Value)(_)
        index = index + 1
    }

    result = ..ok value
}

_write_multibyte_uint_at := #(.Value: Type: UInt) (
    .bytes  : MutableArrayView#(.t: UInt8),
    .offset : UIntNative                    = 0,
    .value  : Value,
    .order  : ByteOrder
) -> (.result: Errable#(Void, (..out_of_bounds))) {
    width ::= size_of(.type = Value)
    -- Prove the whole range before any destination byte changes.
    if [
        _binary_range(.length = length(&bytes).count, .offset = offset, .width = width).ok
        == false
    ] {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    remaining :: Value = value
    last ::= width - 1
    index :: UIntNative = 0

    while index < width {
        position :: UIntNative = index
        if order == ..big { position = last - index }
        byte ::= get_mutable_reference($&bytes, .index = offset + position)!
        byte&= unwrap_or_abort(.value = [remaining % 256] | convert#(.to: UInt8)(_))
        remaining = remaining / 256
        index = index + 1
    }

    result = ..ok Void()
}

read_uint16_at := _read_multibyte_uint_at#(.Value: UInt16)
read_uint32_at := _read_multibyte_uint_at#(.Value: UInt32)
read_uint64_at := _read_multibyte_uint_at#(.Value: UInt64)
write_uint16_at := _write_multibyte_uint_at#(.Value: UInt16)
write_uint32_at := _write_multibyte_uint_at#(.Value: UInt32)
write_uint64_at := _write_multibyte_uint_at#(.Value: UInt64)
