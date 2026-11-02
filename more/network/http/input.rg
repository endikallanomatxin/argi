-- The adapter retains unread bytes between head and body reads. Both the
-- underlying reader and initialized storage must outlive the adapter.
HttpReader := #(.t: Type: BlockReader#(t)) (
    ._reader : $&t
    ._buffer : MutableArrayView#(.t: UInt8)
    ._start  : UIntNative
    ._end    : UIntNative
)

HttpReaderInitArgs: Type = #(.t: Type: BlockReader#(t)) (
    .reader : $&t
    .buffer : MutableArrayView#(.t: UInt8)
)

implement#(.t: Type: BlockReader#(t)) Init#(HttpReader#(t), HttpReaderInitArgs#(t)) (
    .Result : Type = HttpReader#(t)
    .init   = HttpReaderInitArgs#(t) -> (.result: Result) {
        result = (._reader = reader, ._buffer = buffer, ._start = 0, ._end = 0)
    }
)

implement#(.t: Type: BlockReader#(t)) BlockReader#(HttpReader#(t)) (
    .read_block = (.self: $&HttpReader#(t), .buffer: MutableArrayView#(.t: UInt8)) -> (
        .result : Errable#(UIntNative, (..stream_read_failed))
    ) {
        size ::= length(&buffer).count
        if size == 0 {
            result = ..ok 0
            return
        }
        capacity ::= length(&self&._buffer).count
        if capacity == 0 {
            result = BlockReader#().read_block(self&._reader, .buffer = buffer)
            return
        }
        if self&._start == self&._end {
            -- Large body reads can go directly to caller storage. Small head
            -- and framing reads share the retained input buffer.
            if size >= capacity {
                result = BlockReader#().read_block(self&._reader, .buffer = buffer)
                return
            }
            count ::= BlockReader#().read_block(self&._reader, .buffer = self&._buffer)!
            if count > capacity { abort }
            self&._start = 0
            self&._end = count
        }
        count ::= self&._end - self&._start
        if count > size { count = size }
        i :: UIntNative = 0
        while i < count {
            byte ::= unwrap_or_abort(.value = get(&self&._buffer, .index = [self&._start + i]))
            destination ::= unwrap_or_abort(
                .value = get_mutable_reference($&buffer, .index = i)
            )
            destination&= byte
            i = i + 1
        }
        self&._start = self&._start + count
        result = ..ok count
    }
)

implement#(.t: Type: BlockReader#(t)) Reader#(HttpReader#(t)) (
    .read_byte = (.self: $&HttpReader#(t)) -> (
        .result : Errable#(ReadByte, (..stream_read_failed))
    ) {
        storage :: [1]UInt8 = (0)
        count ::= BlockReader#().read_block(self, .buffer = view($&storage))!
        if count == 0 { result = ..ok ..end } else { result = ..ok ..ok storage[0] }
    }
)

-- Reading one byte at a time avoids losing body bytes when the source is not
-- buffered. Use HttpReader to amortize reads from a socket.
read_request := #(.t: Type: BlockReader#(t)) (
    .reader: $&t, .buffer: MutableArrayView#(.t: UInt8), .limits: Limits = Limits()
) -> (.result: Errable#(RequestHead, HttpReasons)) {
    capacity ::= length(&buffer).count
    count :: UIntNative = 0
    while count < capacity and count < limits.max_head_bytes {
        destination ::= unwrap_or_abort(.value = slice(&buffer, .start = count, .count = 1))
        got ::= BlockReader#().read_block(reader, .buffer = destination)!
        if got > 1 { abort }
        if got == 0 {
            result = ..error(.reason = ..unexpected_eof)
            return
        }
        count = count + 1
        if count >= 4 {
            if [
                unwrap_or_abort(.value = get(&buffer, .index = [count - 4])) == 13
                and unwrap_or_abort(.value = get(&buffer, .index = [count - 3])) == 10
                and unwrap_or_abort(.value = get(&buffer, .index = [count - 2])) == 13
                and unwrap_or_abort(.value = get(&buffer, .index = [count - 1])) == 10
            ] {
                prefix ::= unwrap_or_abort(.value = slice(&buffer, .start = 0, .count = count))
                result = parse_request(.bytes = as_readonly(&prefix).view, .limits = limits)
                return
            }
        }
    }
    result = ..error(.reason = ..head_too_large)
}
