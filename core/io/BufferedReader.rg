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
    .buffer   : $&UInt8
    .capacity : UIntNative
    .start    : UIntNative
    .end      : UIntNative
)

init#(.base_type: Type: Reader)(
    .p: $&BufferedReader#(.base_type: base_type),
    .allocator: $&CAllocator = #reach allocator, system.allocator,
    .base: $&base_type,
    .capacity: UIntNative,
) -> () #trusted_temporal := {
    actual_capacity ::= capacity
    one :: UIntNative = 1

    if actual_capacity == 0 {
        actual_capacity = one
    }

    p& = (
        .base = base,
        .buffer = allocate(.self = allocator, .size = actual_capacity),
        .capacity = actual_capacity,
        .start = 0,
        .end = 0,
    )
}

deinit#(.base_type: Type: Reader)(
    .self: $$&BufferedReader#(.base_type: base_type),
    .allocator: $&CAllocator = #reach allocator, system.allocator,
) -> () #invalidates(self) #invalidates_dependency(self, buffer) := {
    deallocate(.self = allocator, .data = self&.buffer, .size = self&.capacity)
    self& = (
        .base = self&.base,
        .buffer = self&.buffer,
        .capacity = 0,
        .start = 0,
        .end = 0,
    )
}

buffered_reader_byte_address#(.base_type: Type: Reader)(
    .self: &BufferedReader#(.base_type: base_type),
    .index: UIntNative,
) -> (.address: UIntNative) := {
    base :: UIntNative = cast#(.to: UIntNative)(.value = self&.buffer)
    address = base + index
}

read_byte#(.base_type: Type: Reader)(.self: $&BufferedReader#(.base_type: base_type)) -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed))) := {
    if self&.start < self&.end {
        addr :: UIntNative = buffered_reader_byte_address(.self = self, .index = self&.start).address
        ptr : &UInt8 = cast#(.to: &UInt8)(.value = addr)
        result = ..ok ..ok ptr&
        self& = (
            .base = self&.base,
            .buffer = self&.buffer,
            .capacity = self&.capacity,
            .start = self&.start + 1,
            .end = self&.end,
        )
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
    addr :: UIntNative = buffered_reader_byte_address(.self = self, .index = 0).address
    ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = addr)
    ptr& = payload
    self& = (
        .base = self&.base,
        .buffer = self&.buffer,
        .capacity = self&.capacity,
        .start = 1,
        .end = 1,
    )
    result = ..ok ..ok payload
}

BufferedReader#(.base_type: Type: Reader) implements Reader
