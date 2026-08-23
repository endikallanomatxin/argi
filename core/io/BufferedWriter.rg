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
    .buffer   : $&UInt8
    .capacity : UIntNative
    .length   : UIntNative
)

init#(.base_type: Type: Writer)(
    .p: $&BufferedWriter#(.base_type: base_type),
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
        .length = 0,
    )
}

deinit#(.base_type: Type: Writer)(
    .self: $$&BufferedWriter#(.base_type: base_type),
    .allocator: $&CAllocator = #reach allocator, system.allocator,
) -> () #invalidates(self) #invalidates_dependency(self, buffer) := {
    buffered_writer_flush(.self = self)
    deallocate(.self = allocator, .data = self&.buffer, .size = self&.capacity)
    self& = (
        .base = self&.base,
        .buffer = self&.buffer,
        .capacity = 0,
        .length = 0,
    )
}

buffered_writer_byte_address#(.base_type: Type: Writer)(
    .self: &BufferedWriter#(.base_type: base_type),
    .index: UIntNative,
) -> (.address: UIntNative) := {
    base :: UIntNative = cast#(.to: UIntNative)(.value = self&.buffer)
    address = base + index
}

buffered_writer_flush#(.base_type: Type: Writer)(.self: $&BufferedWriter#(.base_type: base_type)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    i :: UIntNative = 0
    while i < self&.length {
        addr :: UIntNative = buffered_writer_byte_address(.self = self, .index = i).address
        ptr : &UInt8 = cast#(.to: &UInt8)(.value = addr)
        wrote ::= write_byte(.self = self&.base, .byte = ptr&)
        if is(.value = wrote, .variant = ..error) {
            self& = (
                .base = self&.base,
                .buffer = self&.buffer,
                .capacity = self&.capacity,
                .length = 0,
            )
            result = ..error(.reason = wrote..error.reason)
            return
        }
        i = i + 1
    }

    flushed ::= flush(.self = self&.base)
    if is(.value = flushed, .variant = ..error) {
        self& = (
            .base = self&.base,
            .buffer = self&.buffer,
            .capacity = self&.capacity,
            .length = 0,
        )
        result = ..error(.reason = flushed..error.reason)
        return
    }

    self& = (
        .base = self&.base,
        .buffer = self&.buffer,
        .capacity = self&.capacity,
        .length = 0,
    )
    result = ..ok Void()
}

write_byte#(.base_type: Type: Writer)(.self: $&BufferedWriter#(.base_type: base_type), .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    addr :: UIntNative = buffered_writer_byte_address(.self = self, .index = self&.length).address
    ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = addr)
    ptr& = byte
    next_length ::= self&.length + 1
    self& = (
        .base = self&.base,
        .buffer = self&.buffer,
        .capacity = self&.capacity,
        .length = next_length,
    )

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
