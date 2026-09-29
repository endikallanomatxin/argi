BufferedWriter#(.base_type: Type: Writer) : Type = (
    --
    -- Owning buffered writer wrapper.
    --
    -- The wrapper owns only its internal byte buffer. The underlying `.base`
    -- writer remains borrowed and is not deinitialized here.
    --
    -- Pending buffered bytes are flushed on `deinit()`, after which the
    -- internal buffer storage becomes invalid.
    --
    .base     : $&base_type
    .buffer   : Allocation
    .capacity : UIntNative
    .length   : UIntNative
)

init#(.base_type: Type: Writer)(
    .p: $&BufferedWriter#(.base_type: base_type),
    .allocator: $&Allocator,
    .base: $&base_type,
    .capacity: UIntNative,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    assume allocator

    actual_capacity ::= capacity
    one :: UIntNative = 1

    if actual_capacity == 0 {
        actual_capacity = one
    }

    buffer ::= allocate(.self = allocator, .size = actual_capacity)!
    p& = (
        .base = base,
        .buffer = ~buffer,
        .capacity = actual_capacity,
        .length = 0,
    )
    result = ..ok Void()
}

deinit#(.base_type: Type: Writer)(
    .self: $&BufferedWriter#(.base_type: base_type),
    .allocator: $&Allocator,
) -> () := {
    assume allocator

    buffered_writer_flush(.self = self)
    deinit(.self = $&self&.buffer)
}

buffered_writer_byte_address#(.base_type: Type: Writer)(
    .self: &BufferedWriter#(.base_type: base_type),
    .index: UIntNative,
) -> (.address: UIntNative) := {
    base :: UIntNative = self&.buffer.data.address
    address = base + index
}

buffered_writer_flush#(.base_type: Type: Writer)(.self: $&BufferedWriter#(.base_type: base_type)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    i :: UIntNative = 0
    while i < self&.length {
        ptr ::= _trusted_allocation_byte_ro(.allocation = &self&.buffer, .offset = i).reference
        wrote ::= write_byte(.self = self&.base, .byte = ptr&)
        if is(.value = wrote, .variant = ..error) {
            self&.length = 0
            result = ..error(.reason = wrote..error.reason)
            return
        }
        i = i + 1
    }

    flushed ::= flush(.self = self&.base)
    if is(.value = flushed, .variant = ..error) {
        self&.length = 0
        result = ..error(.reason = flushed..error.reason)
        return
    }

    self&.length = 0
    result = ..ok Void()
}

write_byte#(.base_type: Type: Writer)(.self: $&BufferedWriter#(.base_type: base_type), .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    ptr ::= _trusted_allocation_byte_rw(.allocation = $&self&.buffer, .offset = self&.length).reference
    ptr& = byte
    next_length ::= self&.length + 1
    self&.length = next_length

    if next_length == self&.capacity {
        result = buffered_writer_flush(.self = self)
        return
    }

    result = ..ok Void()
}

flush#(.base_type: Type: Writer)(.self: $&BufferedWriter#(.base_type: base_type)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    result = buffered_writer_flush(.self = self)
}

BufferedWriter#(.base_type: Type: Writer) implements Writer
