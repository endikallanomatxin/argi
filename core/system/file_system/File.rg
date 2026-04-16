FileOpenMode : Type = (
    ..read
    ..write
    ..append
)
..file_open_failed

File : Type = (
    .handle       : UIntNative = 0
    .should_close : Bool = 0 == 1
)

init(
    .p: $&File,
    .handle: UIntNative,
    .should_close: Bool,
) -> () := {
    p& = (
        .handle = handle,
        .should_close = should_close,
    )
}

is_open(.self: &File) -> (.ok: Bool) := {
    ok = self&.handle != 0
}

file_open_mode_c_string(
    .mode: FileOpenMode,
) -> (.text: &Char) := {
    if is(.value = mode, .variant = ..read) {
        text = "rb"
        return
    }

    if is(.value = mode, .variant = ..write) {
        text = "wb"
        return
    }

    text = "ab"
}

file_stream_pointer(.self: &File) -> (.stream: &Any) := {
    stream = cast#(.to: &Any)(.value = self&.handle)
}

open(
    .p: $&File,
    .path: &Char,
    .mode: FileOpenMode,
) -> (.result: Errable#(.t: Bool, .reasons: (..file_open_failed))) := {
    mode_text ::= file_open_mode_c_string(.mode = mode)
    opened : &Any = fopen(.path = path, .mode = mode_text)
    p& = (
        .handle = cast#(.to: UIntNative)(.value = opened),
        .should_close = 1 == 1,
    )
    if p&.handle == 0 {
        result = ..error(.reason = ..file_open_failed)
        return
    }
    result = ..ok 1 == 1
}

open_read(
    .p: $&File,
    .path: &Char,
) -> (.result: Errable#(.t: Bool, .reasons: (..file_open_failed))) := {
    result = open(.p = p, .path = path, .mode = ..read)
}

open_write(
    .p: $&File,
    .path: &Char,
) -> (.result: Errable#(.t: Bool, .reasons: (..file_open_failed))) := {
    result = open(.p = p, .path = path, .mode = ..write)
}

open_append(
    .p: $&File,
    .path: &Char,
) -> (.result: Errable#(.t: Bool, .reasons: (..file_open_failed))) := {
    result = open(.p = p, .path = path, .mode = ..append)
}

init_stdin(.p: $&File) -> () := {
    mode_text ::= file_open_mode_c_string(.mode = ..read)
    stream : &Any = fdopen(.fd = 0, .mode = mode_text)
    p& = (
        .handle = cast#(.to: UIntNative)(.value = stream),
        .should_close = 0 == 1,
    )
}

init_stdout(.p: $&File) -> () := {
    mode_text ::= file_open_mode_c_string(.mode = ..write)
    stream : &Any = fdopen(.fd = 1, .mode = mode_text)
    p& = (
        .handle = cast#(.to: UIntNative)(.value = stream),
        .should_close = 0 == 1,
    )
}

init_stderr(.p: $&File) -> () := {
    mode_text ::= file_open_mode_c_string(.mode = ..write)
    stream : &Any = fdopen(.fd = 2, .mode = mode_text)
    p& = (
        .handle = cast#(.to: UIntNative)(.value = stream),
        .should_close = 0 == 1,
    )
}

close(.self: $&File) -> (.result: Errable#(.t: Void, .reasons: (..stream_close_failed))) := {
    if self&.handle == 0 {
        result = ..ok Void()
        return
    }

    close_failed :: Bool = false
    if self&.should_close {
        stream ::= file_stream_pointer(.self = self).stream
        close_status ::= fclose(.stream = stream).status
        close_failed = close_status != 0
    }

    self& = (
        .handle = 0,
        .should_close = 0 == 1,
    )

    if close_failed {
        result = ..error(.reason = ..stream_close_failed)
        return
    }

    result = ..ok Void()
}

flush(.self: $&File) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    if self&.handle == 0 {
        result = ..error(.reason = ..stream_flush_failed)
        return
    }

    if fflush(.stream = file_stream_pointer(.self = self).stream).status != 0 {
        result = ..error(.reason = ..stream_flush_failed)
        return
    }

    result = ..ok Void()
}

read_byte(.self: $&File) -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed))) := {
    if self&.handle == 0 {
        result = ..error(.reason = ..stream_read_failed)
        return
    }

    byte :: UInt8 = 0
    byte_view ::= array_view#(.t: UInt8)(
        .data = $&byte,
        .length = 1,
    )
    read_count ::= fread_into(
        .buffer = byte_view,
        .stream = file_stream_pointer(.self = self).stream,
    ).count

    if read_count == 0 {
        stream ::= file_stream_pointer(.self = self).stream
        if ferror(.stream = stream).status != 0 {
            result = ..error(.reason = ..stream_read_failed)
            return
        }

        if feof(.stream = stream).status != 0 {
            result = ..ok ..end
            return
        }

        result = ..error(.reason = ..stream_read_failed)
        return
    }

    result = ..ok ..ok byte
}

write_byte(.self: $&File, .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    if self&.handle == 0 {
        result = ..error(.reason = ..stream_write_failed)
        return
    }

    single_byte :: UInt8 = byte
    byte_view ::= array_view#(.t: UInt8)(
        .data = $&single_byte,
        .length = 1,
    )
    wrote ::= fwrite_from(
        .buffer = byte_view,
        .stream = file_stream_pointer(.self = self).stream,
    ).count

    if wrote != 1 {
        result = ..error(.reason = ..stream_write_failed)
        return
    }

    result = ..ok Void()
}

read(
    .self: $&File,
    .buffer: ArrayView#(.t: UInt8),
) -> (.result: Errable#(.t: UIntNative, .reasons: (..stream_read_failed))) := {
    if self&.handle == 0 {
        result = ..error(.reason = ..stream_read_failed)
        return
    }

    stream ::= file_stream_pointer(.self = self).stream
    read_count ::= fread_into(.buffer = buffer, .stream = stream).count

    if read_count < buffer.length {
        if ferror(.stream = stream).status != 0 {
            result = ..error(.reason = ..stream_read_failed)
            return
        }
    }

    result = ..ok read_count
}

write(
    .self: $&File,
    .buffer: ArrayView#(.t: UInt8),
) -> (.result: Errable#(.t: UIntNative, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    if self&.handle == 0 {
        result = ..error(.reason = ..stream_write_failed)
        return
    }

    stream ::= file_stream_pointer(.self = self).stream
    wrote ::= fwrite_from(.buffer = buffer, .stream = stream).count

    if wrote < buffer.length {
        if ferror(.stream = stream).status != 0 {
            result = ..error(.reason = ..stream_write_failed)
            return
        }
    }

    result = ..ok wrote
}

File implements Reader
File implements Writer

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
) -> () := {
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
    .self: $&BufferedReader#(.base_type: base_type),
    .allocator: $&CAllocator = #reach allocator, system.allocator,
) -> () := {
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
) -> () := {
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
    .self: $&BufferedWriter#(.base_type: base_type),
    .allocator: $&CAllocator = #reach allocator, system.allocator,
) -> () := {
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
