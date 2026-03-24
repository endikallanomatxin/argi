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

file_stream_pointer(.self: &File) -> (.stream: &Any) := {
    stream = cast#(.to: &Any)(.value = self&.handle)
}

file_open(
    .p: $&File,
    .path: &Char,
    .mode: &Char,
) -> () := {
    opened : $&Any = fopen(.path = path, .mode = mode)
    p& = (
        .handle = cast#(.to: UIntNative)(.value = opened),
        .should_close = 1 == 1,
    )
}

open_read(
    .p: $&File,
    .path: &Char,
) -> () := {
    file_open(.p = p, .path = path, .mode = "rb")
}

open_write(
    .p: $&File,
    .path: &Char,
) -> () := {
    file_open(.p = p, .path = path, .mode = "wb")
}

open_append(
    .p: $&File,
    .path: &Char,
) -> () := {
    file_open(.p = p, .path = path, .mode = "ab")
}

init_stdin(.p: $&File) -> () := {
    stream : $&Any = fdopen(.fd = 0, .mode = "rb")
    p& = (
        .handle = cast#(.to: UIntNative)(.value = stream),
        .should_close = 0 == 1,
    )
}

init_stdout(.p: $&File) -> () := {
    stream : $&Any = fdopen(.fd = 1, .mode = "wb")
    p& = (
        .handle = cast#(.to: UIntNative)(.value = stream),
        .should_close = 0 == 1,
    )
}

init_stderr(.p: $&File) -> () := {
    stream : $&Any = fdopen(.fd = 2, .mode = "wb")
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
    .file : $&File
)

init(.p: $&FileReader, .file: $&File) -> () := {
    p& = (
        .file = file
    )
}

read_byte(.self: $&FileReader) -> (.result: ReadByte) := {
    result = read_byte(.self = self&.file)
}

FileReader implements Reader

FileWriter : Type = (
    .file : $&File
)

init(.p: $&FileWriter, .file: $&File) -> () := {
    p& = (
        .file = file
    )
}

write_byte(.self: $&FileWriter, .byte: UInt8) -> () := {
    write_byte(.self = self&.file, .byte = byte)
}

flush(.self: $&FileWriter) -> () := {
    flush(.self = self&.file)
}

FileWriter implements Writer

BufferedReader : Type = (
    .reader   : $&FileReader
    .buffer   : $&UInt8
    .capacity : UIntNative
    .start    : UIntNative
    .end      : UIntNative
)

init(
    .p: $&BufferedReader,
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .reader: $&FileReader,
    .capacity: UIntNative,
) -> () := {
    actual_capacity ::= capacity
    one :: UIntNative = 1

    if actual_capacity == 0 {
        actual_capacity = one
    }

    p& = (
        .reader = reader,
        .buffer = allocate(.self = allocator, .size = actual_capacity),
        .capacity = actual_capacity,
        .start = 0,
        .end = 0,
    )
}

deinit(
    .self: $&BufferedReader,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    deallocate(.self = allocator, .data = self&.buffer, .size = self&.capacity)
    self& = (
        .reader = self&.reader,
        .buffer = self&.buffer,
        .capacity = 0,
        .start = 0,
        .end = 0,
    )
}

buffered_reader_byte_address(
    .self: &BufferedReader,
    .index: UIntNative,
) -> (.address: UIntNative) := {
    base :: UIntNative = cast#(.to: UIntNative)(.value = self&.buffer)
    address = base + index
}

read_byte(.self: $&BufferedReader) -> (.result: ReadByte) := {
    _ ::= buffered_reader_byte_address(.self = self, .index = 0)
    result = read_byte(.self = self&.reader)
}

BufferedReader implements Reader

BufferedWriter : Type = (
    .writer   : $&FileWriter
    .buffer   : $&UInt8
    .capacity : UIntNative
    .length   : UIntNative
)

init(
    .p: $&BufferedWriter,
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .writer: $&FileWriter,
    .capacity: UIntNative,
) -> () := {
    actual_capacity ::= capacity
    one :: UIntNative = 1

    if actual_capacity == 0 {
        actual_capacity = one
    }

    p& = (
        .writer = writer,
        .buffer = allocate(.self = allocator, .size = actual_capacity),
        .capacity = actual_capacity,
        .length = 0,
    )
}

deinit(
    .self: $&BufferedWriter,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    deallocate(.self = allocator, .data = self&.buffer, .size = self&.capacity)
    self& = (
        .writer = self&.writer,
        .buffer = self&.buffer,
        .capacity = 0,
        .length = 0,
    )
}

buffered_writer_byte_address(
    .self: &BufferedWriter,
    .index: UIntNative,
) -> (.address: UIntNative) := {
    base :: UIntNative = cast#(.to: UIntNative)(.value = self&.buffer)
    address = base + index
}

write_byte(.self: $&BufferedWriter, .byte: UInt8) -> () := {
    if self&.length < self&.capacity {
        addr :: UIntNative = buffered_writer_byte_address(.self = self, .index = self&.length).address
        ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = addr)
        ptr& = byte
        self& = (
            .writer = self&.writer,
            .buffer = self&.buffer,
            .capacity = self&.capacity,
            .length = self&.length + 1,
        )
        return
    }

    write_byte(.self = self&.writer, .byte = byte)
}

flush(.self: $&BufferedWriter) -> () := {
    flush(.self = self&.writer)
    self& = (
        .writer = self&.writer,
        .buffer = self&.buffer,
        .capacity = self&.capacity,
        .length = 0,
    )
}

BufferedWriter implements Writer
