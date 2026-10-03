BufferedReader#(.base_type: Type: Reader) : Type = (
    --
    -- Owning buffered reader wrapper.
    --
    -- The wrapper owns only its internal byte buffer. The underlying `.base`
    -- stream remains borrowed and is not closed or deinitialized here.
    --
    -- Bytes returned by `read_byte()` are copied out of the buffer, so callers
    -- do not borrow storage tied to this wrapper's lifetime.
    --
    .base     : $&base_type
    .buffer   : Allocation
    .capacity : UIntNative
    .start    : UIntNative
    .end      : UIntNative
)

BufferedReader init#(.base_type: Type: Reader)(.allocator: $&Allocator,
    .base: $&base_type,
    .capacity: UIntNative,
) -> (.result: Errable#(.t: BufferedReader#(.base_type: base_type), .reasons: (..out_of_memory))) := {
    constructed :: BufferedReader#(.base_type: base_type)

    assume allocator

    actual_capacity ::= capacity
    one :: UIntNative = 1

    if actual_capacity == 0 {
        actual_capacity = one
    }

    buffer ::= allocate(.self = allocator, .size = actual_capacity)!
    constructed = (
        .base = base,
        .buffer = ~buffer,
        .capacity = actual_capacity,
        .start = 0,
        .end = 0,
    )
    result = ..ok ~constructed
}

BufferedReader deinit#(.base_type: Type: Reader)(
    .self: $&BufferedReader#(.base_type: base_type),
    .allocator: $&Allocator,
) -> () := {
    assume allocator

    deinit(.self = $&self&.buffer)
}

read_byte#(.base_type: Type: Reader)(.self: $&BufferedReader#(.base_type: base_type)) -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed))) := {
    if self&.start < self&.end {
        ptr ::= _trusted_allocation_byte_ro(.allocation = &self&.buffer, .offset = self&.start).reference
        result = ..ok ..ok ptr&
        self&.start = self&.start + 1
        return
    }

    if self&.capacity == 0 {
        result = read_byte(.self = self&.base)
        return
    }

    first ::= read_byte(.self = self&.base)
    if is(.value = first, .variant = ..error) {
        result = ..error(.reason = first..error.reason)
        return
    }

    first_payload ::= first..ok
    if is(.value = first_payload, .variant = ..end) {
        result = ..ok ..end
        return
    }

    payload ::= first_payload..ok
    ptr ::= _trusted_allocation_byte_rw(.allocation = $&self&.buffer, .offset = 0).reference
    ptr& = payload
    self&.start = 1
    self&.end = 1
    result = ..ok ..ok payload
}

BufferedReader#(.base_type: Type: Reader) implements Reader
