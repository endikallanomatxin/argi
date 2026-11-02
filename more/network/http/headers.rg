Header := (.name: ArrayView#(.t: UInt8), .value: ArrayView#(.t: UInt8))

implement ImplicitlyCopyable#(Header) ()

HeaderIterator := (._bytes: ArrayView#(.t: UInt8), ._position: UIntNative)

headers := (.self: &RequestHead) -> (.iterator: HeaderIterator) {
    iterator = (._bytes = self&.bytes, ._position = self&._headers_at)
}

next := (.self: $&HeaderIterator) -> (.value: ?Header = ..none) {
    bytes ::= self&._bytes
    i ::= self&._position
    if i >= length(&bytes).count or _byte(.bytes = bytes, .index = i).value == 13 { return }
    start ::= i
    size ::= length(&bytes).count
    while i < size {
        if _byte(.bytes = bytes, .index = i).value == 58 { break }
        i = i + 1
    }
    if i == size { return }
    name ::= _slice(.bytes = bytes, .start = start, .end = i).value
    i = i + 1
    start = i
    while i < size {
        if _byte(.bytes = bytes, .index = i).value == 13 { break }
        i = i + 1
    }
    if i == size or size - i < 2 { return }
    if _byte(.bytes = bytes, .index = [i + 1]).value != 10 { return }
    end ::= i
    self&._position = i + 2
    while start < end {
        byte ::= _byte(.bytes = bytes, .index = start).value
        if byte != 32 and byte != 9 { break }
        start = start + 1
    }
    while end > start {
        byte ::= _byte(.bytes = bytes, .index = [end - 1]).value
        if byte != 32 and byte != 9 { break }
        end = end - 1
    }
    value = ..some(
        .value = (
            .name  = name
            .value = _slice(.bytes = bytes, .start = start, .end = end).value
        )
    )
}

header := (.self: &RequestHead, .name: StringView) -> (.value: ?Header = ..none) {
    iterator ::= headers(self)
    while true {
        match next($&iterator).value {
            ..none { return }
            ..some item {
                if _ascii_equal(.bytes = item.value.name, .text = name).ok {
                    value = ..some(.value = item.value)
                    return
                }
            }
        }
    }
}
