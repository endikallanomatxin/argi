BufferedWriter#(.base_type: Type: Writer) : Type = (
    --
    -- Owning buffered writer wrapper.
    --
    -- The wrapper owns only its internal byte buffer. The underlying `.base`
    -- writer remains borrowed and is not deinitialized here.
    --
    -- Call `flush()` explicitly to handle output errors. Cleanup attempts a
    -- best-effort flush and does not report its failure. A failed write discards
    -- pending bytes because its underlying error cannot report partial progress.
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
    .capacity: UIntNative = 4096,
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
        remaining ::= self&.length - i
        -- Authenticate both endpoints before exposing a contiguous view;
        -- checking only its first byte does not prove the full range fits.
        _ ::= _trusted_allocation_byte_ro(.allocation = &self&.buffer, .offset = self&.length - 1).reference
        -- Only the initialized prefix is exposed and remains borrowed for
        -- the duration of this write.
        ptr ::= _trusted_allocation_byte_rw(.allocation = $&self&.buffer, .offset = i).reference
        view ::= _trusted_array_view#(.t: UInt8)(.data = ptr, .length = remaining)
        wrote ::= write(.self = self&.base, .buffer = view)
        if is(.value = wrote, .variant = ..error) {
            self&.length = 0
            result = ..error(.reason = wrote..error.reason)
            return
        }
        count ::= wrote..ok
        if count == 0 or count > remaining {
            self&.length = 0
            result = ..error(.reason = ..stream_write_failed)
            return
        }
        i = i + count
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
