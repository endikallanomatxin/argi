-- The adapter borrows its source. Reaching the limit reports EOF without
-- reading ahead; the source can be used again after the adapter loan ends.
LimitedReader#(.t: Type: BlockReader): Type = (._source: $&t, ._remaining: UIntNative)

LimitedReader#(.t: Type: BlockReader) implements BlockReader

LimitedReader init#(
        .t : Type: BlockReader
    )(
        .source : $&t,
        .limit  : UIntNative
    ) -> (
        .result : LimitedReader#(.t: t)
    ) := { result = (._source = source, ._remaining = limit) }

remaining#(.t: Type: BlockReader)(.self: &LimitedReader#(.t: t)) -> (.count: UIntNative) := {
    count = self&._remaining
}

read_block#(
        .t : Type: BlockReader
    )(
        .self   : $&LimitedReader#(.t: t),
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(.t: UIntNative, .reasons: (..stream_read_failed))
    ) := {
    count ::= length(.self = &buffer).count
    if self&._remaining < count { count = self&._remaining }
    if count == 0 {
        result = ..ok 0
        return
    }
    bounded ::= unwrap_or_abort(.value = slice(.self = &buffer, .start = 0, .count = count))
    received ::= read_block(.self = self&._source, .buffer = bounded)!
    if received > count { abort }
    self&._remaining = self&._remaining - received
    result = ..ok received
}

-- The block adapter also supports byte consumers without reading ahead.
LimitedReader#(.t: Type: BlockReader) implements Reader

read_byte#(
        .t : Type: BlockReader
    )(
        .self : $&LimitedReader#(.t: t)
    ) -> (
        .result : Errable#(.t: ReadByte, .reasons: (..stream_read_failed))
    ) := {
    byte :: [1]UInt8 = (0)
    received ::= read_block(.self = self, .buffer = view(.array = $&byte))!
    if received == 0 { result = ..ok ..end } else { result = ..ok ..ok byte[0] }
}

-- Byte-only sources need no block protocol. The budget counts delivered bytes.
LimitedByteReader#(.t: Type: Reader): Type = (._source: $&t, ._remaining: UIntNative)

LimitedByteReader#(.t: Type: Reader) implements Reader

LimitedByteReader init#(
        .t : Type: Reader
    )(
        .source : $&t,
        .limit  : UIntNative
    ) -> (
        .result : LimitedByteReader#(.t: t)
    ) := { result = (._source = source, ._remaining = limit) }

remaining#(.t: Type: Reader)(.self: &LimitedByteReader#(.t: t)) -> (.count: UIntNative) := {
    count = self&._remaining
}

read_byte#(
        .t : Type: Reader
    )(
        .self : $&LimitedByteReader#(.t: t)
    ) -> (
        .result : Errable#(.t: ReadByte, .reasons: (..stream_read_failed))
    ) := {
    if self&._remaining == 0 {
        result = ..ok ..end
        return
    }
    byte ::= read_byte(.self = self&._source)!
    match byte { ..end {} ..ok _ { self&._remaining = self&._remaining - 1 } }
    result = ..ok byte
}
