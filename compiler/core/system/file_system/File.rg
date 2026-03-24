FileKind : Type = (
    ..stdin
    ..stdout
    ..stderr
    ..other
)

File : Type = (
    .descriptor : UIntNative
    .kind       : FileKind
)

init(
    .p: $&File,
    .descriptor: UIntNative,
    .kind: FileKind = ..other,
) -> () := {
    p& = (
        .descriptor = descriptor,
        .kind = kind,
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
    -- TODO: bridge real file descriptors/handles to libc or platform syscalls.
    -- `getchar()` returns Int32 and the compiler does not support the casts we
    -- need yet, so keep the lowest-level reader shape in place and stub actual
    -- byte reads for now.
    _ ::= self
    result = ..end
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
    -- Current libc bindings only expose `putchar`, so stdout and stderr share
    -- the same backend for now. Keep the `File` split so the API can grow into
    -- proper descriptors/handles later without changing the layering.
    putchar(.character = byte)
}

flush(.self: $&FileWriter) -> () := {
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
