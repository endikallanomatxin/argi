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
