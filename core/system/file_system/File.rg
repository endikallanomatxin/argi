FileOpenMode : Type = (
    ..read
    ..write
    ..append
)

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
) -> (.text: CString) := {
    if is(.value = mode, .variant = ..read) {
        text = from_literal(.data = "rb")
        return
    }

    if is(.value = mode, .variant = ..write) {
        text = from_literal(.data = "wb")
        return
    }

    text = from_literal(.data = "ab")
}

file_stream_pointer(.self: &File) -> (.stream: &Any) := {
    stream = cast#(.to: &Any)(.value = self&.handle)
}

open(
    .p: $&File,
    .path: CString,
    .mode: FileOpenMode,
) -> () := {
    path_ptr ::= pointer(.self = &path)
    mode_text ::= file_open_mode_c_string(.mode = mode)
    mode_ptr ::= pointer(.self = &mode_text)
    opened : $&Any = fopen(.path = path_ptr, .mode = mode_ptr)
    p& = (
        .handle = cast#(.to: UIntNative)(.value = opened),
        .should_close = 1 == 1,
    )
}

open_read(
    .p: $&File,
    .path: CString,
) -> () := {
    open(.p = p, .path = path, .mode = ..read)
}

open_write(
    .p: $&File,
    .path: CString,
) -> () := {
    open(.p = p, .path = path, .mode = ..write)
}

open_append(
    .p: $&File,
    .path: CString,
) -> () := {
    open(.p = p, .path = path, .mode = ..append)
}

init_stdin(.p: $&File) -> () := {
    mode_text ::= file_open_mode_c_string(.mode = ..read)
    mode_ptr ::= pointer(.self = &mode_text)
    stream : $&Any = fdopen(.fd = 0, .mode = mode_ptr)
    p& = (
        .handle = cast#(.to: UIntNative)(.value = stream),
        .should_close = 0 == 1,
    )
}

init_stdout(.p: $&File) -> () := {
    mode_text ::= file_open_mode_c_string(.mode = ..write)
    mode_ptr ::= pointer(.self = &mode_text)
    stream : $&Any = fdopen(.fd = 1, .mode = mode_ptr)
    p& = (
        .handle = cast#(.to: UIntNative)(.value = stream),
        .should_close = 0 == 1,
    )
}

init_stderr(.p: $&File) -> () := {
    mode_text ::= file_open_mode_c_string(.mode = ..write)
    mode_ptr ::= pointer(.self = &mode_text)
    stream : $&Any = fdopen(.fd = 2, .mode = mode_ptr)
    p& = (
        .handle = cast#(.to: UIntNative)(.value = stream),
        .should_close = 0 == 1,
    )
}

close(.self: $&File) -> () := {
    if self&.handle == 0 {
        return
    }

    if self&.should_close {
        _ ::= fclose(.stream = file_stream_pointer(.self = self).stream)
    }

    self& = (
        .handle = 0,
        .should_close = 0 == 1,
    )
}

flush(.self: $&File) -> () := {
    if self&.handle == 0 {
        return
    }

    _ ::= fflush(.stream = file_stream_pointer(.self = self).stream)
}

read_byte(.self: $&File) -> (.result: ReadByte) := {
    if self&.handle == 0 {
        result = ..end
        return
    }

    byte :: UInt8 = 0
    read_count ::= fread(
        .buffer = $&byte,
        .size = 1,
        .count = 1,
        .stream = file_stream_pointer(.self = self).stream,
    ).count

    if read_count == 0 {
        result = ..end
        return
    }

    result = ..ok(.byte = byte)
}

write_byte(.self: $&File, .byte: UInt8) -> () := {
    if self&.handle == 0 {
        return
    }

    single_byte :: UInt8 = byte
    _ ::= fwrite(
        .buffer = &single_byte,
        .size = 1,
        .count = 1,
        .stream = file_stream_pointer(.self = self).stream,
    )
}

FileReader : Type = (
    .file     : $&File
    .buffer   : $&UInt8
    .capacity : UIntNative
    .start    : UIntNative
    .end      : UIntNative
)

init(
    .p: $&FileReader,
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .file: $&File,
    .capacity: UIntNative,
) -> () := {
    actual_capacity ::= capacity
    one :: UIntNative = 1

    if actual_capacity == 0 {
        actual_capacity = one
    }

    p& = (
        .file = file,
        .buffer = allocate(.self = allocator, .size = actual_capacity),
        .capacity = actual_capacity,
        .start = 0,
        .end = 0,
    )
}

deinit(
    .self: $&FileReader,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    deallocate(.self = allocator, .data = self&.buffer, .size = self&.capacity)
    self& = (
        .file = self&.file,
        .buffer = self&.buffer,
        .capacity = 0,
        .start = 0,
        .end = 0,
    )
}

buffered_reader_byte_address(
    .self: &FileReader,
    .index: UIntNative,
) -> (.address: UIntNative) := {
    base :: UIntNative = cast#(.to: UIntNative)(.value = self&.buffer)
    address = base + index
}

read_byte(.self: $&FileReader) -> (.result: ReadByte) := {
    if self&.start < self&.end {
        addr :: UIntNative = buffered_reader_byte_address(.self = self, .index = self&.start).address
        ptr : &UInt8 = cast#(.to: &UInt8)(.value = addr)
        result = ..ok(.byte = ptr&)
        self& = (
            .file = self&.file,
            .buffer = self&.buffer,
            .capacity = self&.capacity,
            .start = self&.start + 1,
            .end = self&.end,
        )
        return
    }

    if self&.capacity == 0 {
        result = read_byte(.self = self&.file)
        return
    }

    first ::= read_byte(.self = self&.file)
    if is(.value = first, .variant = ..end) {
        result = ..end
        return
    }

    payload ::= first..ok
    addr :: UIntNative = buffered_reader_byte_address(.self = self, .index = 0).address
    ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = addr)
    ptr& = payload.byte
    self& = (
        .file = self&.file,
        .buffer = self&.buffer,
        .capacity = self&.capacity,
        .start = 1,
        .end = 1,
    )
    result = ..ok(.byte = payload.byte)
}

FileReader implements Reader

FileWriter : Type = (
    .file     : $&File
    .buffer   : $&UInt8
    .capacity : UIntNative
    .length   : UIntNative
)

init(
    .p: $&FileWriter,
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .file: $&File,
    .capacity: UIntNative,
) -> () := {
    actual_capacity ::= capacity
    one :: UIntNative = 1

    if actual_capacity == 0 {
        actual_capacity = one
    }

    p& = (
        .file = file,
        .buffer = allocate(.self = allocator, .size = actual_capacity),
        .capacity = actual_capacity,
        .length = 0,
    )
}

deinit(
    .self: $&FileWriter,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    file_writer_flush(.self = self)
    deallocate(.self = allocator, .data = self&.buffer, .size = self&.capacity)
    self& = (
        .file = self&.file,
        .buffer = self&.buffer,
        .capacity = 0,
        .length = 0,
    )
}

buffered_writer_byte_address(
    .self: &FileWriter,
    .index: UIntNative,
) -> (.address: UIntNative) := {
    base :: UIntNative = cast#(.to: UIntNative)(.value = self&.buffer)
    address = base + index
}

file_writer_flush(.self: $&FileWriter) -> () := {
    i :: UIntNative = 0
    while i < self&.length {
        addr :: UIntNative = buffered_writer_byte_address(.self = self, .index = i).address
        ptr : &UInt8 = cast#(.to: &UInt8)(.value = addr)
        write_byte(.self = self&.file, .byte = ptr&)
        i = i + 1
    }

    flush(.self = self&.file)
    self& = (
        .file = self&.file,
        .buffer = self&.buffer,
        .capacity = self&.capacity,
        .length = 0,
    )
}

write_byte(.self: $&FileWriter, .byte: UInt8) -> () := {
    addr :: UIntNative = buffered_writer_byte_address(.self = self, .index = self&.length).address
    ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = addr)
    ptr& = byte
    next_length ::= self&.length + 1
    self& = (
        .file = self&.file,
        .buffer = self&.buffer,
        .capacity = self&.capacity,
        .length = next_length,
    )

    if next_length == self&.capacity {
        file_writer_flush(.self = self)
    }
}

flush(.self: $&FileWriter) -> () := {
    file_writer_flush(.self = self)
}

FileWriter implements Writer
