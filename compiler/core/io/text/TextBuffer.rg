TextBuffer : Type = (
    .data     : $&UInt8
    .length   : UIntNative
    .capacity : UIntNative
)

init(
    .p: $&TextBuffer,
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .capacity: UIntNative,
) -> () := {
    actual_capacity ::= capacity
    one :: UIntNative = 1

    if actual_capacity == 0 {
        actual_capacity = one
    }

    p& = (
        .data = allocate(.self = allocator, .size = actual_capacity),
        .length = 0,
        .capacity = actual_capacity,
    )
}

deinit(
    .self: $&TextBuffer,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    deallocate(.self = allocator, .data = self&.data, .size = self&.capacity)
    self& = (
        .data = self&.data,
        .length = 0,
        .capacity = 0,
    )
}

text_buffer_byte_address(
    .self: &TextBuffer,
    .index: UIntNative,
) -> (.address: UIntNative) := {
    base :: UIntNative = cast#(.to: UIntNative)(.value = self&.data)
    address = base + index
}

clear(.self: $&TextBuffer) -> () := {
    self& = (
        .data = self&.data,
        .length = 0,
        .capacity = self&.capacity,
    )
}

push_byte(.self: $&TextBuffer, .byte: UInt8) -> () := {
    if self&.length == self&.capacity {
        return
    }

    addr :: UIntNative = text_buffer_byte_address(.self = self, .index = self&.length).address
    ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = addr)
    ptr& = byte
    self& = (
        .data = self&.data,
        .length = self&.length + 1,
        .capacity = self&.capacity,
    )
}

byte_at(
    .self: &TextBuffer,
    .index: UIntNative,
) -> (.byte: UInt8) := {
    addr :: UIntNative = text_buffer_byte_address(.self = self, .index = index).address
    ptr : &UInt8 = cast#(.to: &UInt8)(.value = addr)
    byte = ptr&
}

as_c_string_address(.self: &TextBuffer) -> (.address: UIntNative) := {
    address = cast#(.to: UIntNative)(.value = self&.data)
}

write_text_buffer(
    .writer: $&Writer,
    .buffer: &TextBuffer,
) -> () := {
    i :: UIntNative = 0
    while i < buffer&.length {
        addr :: UIntNative = text_buffer_byte_address(.self = buffer, .index = i).address
        ptr : &UInt8 = cast#(.to: &UInt8)(.value = addr)
        write_byte(.self = writer, .byte = ptr&)
        i = i + 1
    }
}

push_c_string(
    .self: $&TextBuffer,
    .text: &Char,
) -> () := {
    i :: UIntNative = 0
    while 1 == 1 {
        addr :: UIntNative = cast#(.to: UIntNative)(.value = text) + i
        ptr : &UInt8 = cast#(.to: &UInt8)(.value = addr)
        if ptr& == 0 {
            break
        }

        push_byte(.self = self, .byte = ptr&)
        i = i + 1
    }
}

write_line_text_buffer(
    .writer: $&Writer,
    .buffer: &TextBuffer,
) -> () := {
    write_text_buffer(.writer = writer, .buffer = buffer)
    write_byte(.self = writer, .byte = 10)
}
