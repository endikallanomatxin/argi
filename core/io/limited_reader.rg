-- The adapter borrows its source. Reaching the limit reports EOF without
-- reading ahead; the source can be used again after the adapter loan ends.
LimitedReader := #(.t: Type: BlockReader#(t)) (._source: $&t, ._remaining: UIntNative)

LimitedReaderInitArgs: Type = #(.t: Type: BlockReader#(t)) (.source: $&t, .limit: UIntNative)

implement#(.t: Type: BlockReader#(t)) Init#(LimitedReader#(.t: t), LimitedReaderInitArgs#(t)) (
    .Result : Type = LimitedReader#(.t: t)

    .init = LimitedReaderInitArgs#(t) -> (.result: Result) {
        _init_source ::= source
        _init_limit ::= limit

        result = (._source = _init_source, ._remaining = _init_limit)
    }
)

_limited_block_remaining := #(.t: Type: BlockReader#(t)) (.self: &LimitedReader#(.t: t)) -> (
    .count : UIntNative
) {
    count = self&._remaining
}

implement#(.t: Type: BlockReader#(t)) BlockReader#(LimitedReader#(.t: t)) (
    .read_block = (.self: $&LimitedReader#(.t: t), .buffer: MutableArrayView#(.t: UInt8)) -> (
        .result : Errable#(UIntNative, (..stream_read_failed))
    ) {

        count ::= length(&buffer).count

        if self&._remaining < count { count = self&._remaining }
        if count == 0 {
            result = ..ok 0
            return
        }

        bounded ::= unwrap_or_abort(.value = slice(&buffer, .start = 0, .count = count))
        received ::= BlockReader#().read_block(self&._source, .buffer = bounded)!

        if received > count { abort }
        self&._remaining = self&._remaining - received

        result = ..ok received
    }
)

-- The block adapter also supports byte consumers without reading ahead.
implement#(.t: Type: BlockReader#(t)) Reader#(LimitedReader#(.t: t)) (
    .read_byte = (.self: $&LimitedReader#(.t: t)) -> (
        .result : Errable#(ReadByte, (..stream_read_failed))
    ) {

        byte :: [1]UInt8 = (0)
        received ::= BlockReader#().read_block(self, .buffer = view($&byte))!

        if received == 0 { result = ..ok ..end } else { result = ..ok ..ok byte[0] }
    }

)

-- Byte-only sources need no block protocol. The budget counts delivered bytes.
LimitedByteReader := #(.t: Type: Reader#(t)) (._source: $&t, ._remaining: UIntNative)

LimitedByteReaderInitArgs: Type = #(.t: Type: Reader#(t)) (.source: $&t, .limit: UIntNative)

implement#(.t: Type: Reader#(t)) Init#(LimitedByteReader#(.t: t), LimitedByteReaderInitArgs#(t)) (
    .Result : Type = LimitedByteReader#(.t: t)

    .init = LimitedByteReaderInitArgs#(t) -> (.result: Result) {
        _init_source ::= source
        _init_limit ::= limit

        result = (._source = _init_source, ._remaining = _init_limit)
    }
)

_limited_byte_remaining := #(.t: Type: Reader#(t)) (.self: &LimitedByteReader#(.t: t)) -> (
    .count : UIntNative
) {
    count = self&._remaining
}

implement#(.t: Type: Reader#(t)) Reader#(LimitedByteReader#(.t: t)) (
    .read_byte = (.self: $&LimitedByteReader#(.t: t)) -> (
        .result : Errable#(ReadByte, (..stream_read_failed))
    ) {

        if self&._remaining == 0 {
            result = ..ok ..end
            return
        }

        byte ::= Reader#().read_byte(self&._source)!

        match byte { ..end {} ..ok _ { self&._remaining = self&._remaining - 1 } }

        result = ..ok byte
    }

)

implement#(.t: Type: BlockReader#(t)) ReadLimit#(LimitedReader#(.t: t)) (
    .remaining_bytes = _limited_block_remaining
)

implement#(.t: Type: Reader#(t)) ReadLimit#(LimitedByteReader#(.t: t)) (
    .remaining_bytes = _limited_byte_remaining
)
