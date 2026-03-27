FileSystem : Type = ()

once init(.p: $&FileSystem) -> () := {
}

exists(
    .self: &FileSystem,
    .path: CString,
) -> (.ok: Bool) := {
    path_ptr ::= pointer(.self = &path)
    ok = access(.path = path_ptr, .mode = 0).status == 0
}

exists(
    .self: &FileSystem,
    .path: &String,
) -> (.ok: Bool) := {
    c_path ::= as_c_string(.self = path)
    ok = exists(.self = self, .path = c_path).ok
}

exists(
    .self: &FileSystem,
    .path: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.ok: Bool) := {
    c_path ::= as_c_string(.self = path, .allocator = allocator)
    ok = exists(.self = self, .path = c_path.text).ok
}

remove(
    .self: &FileSystem,
    .path: CString,
) -> (.ok: Bool) := {
    path_ptr ::= pointer(.self = &path)
    _ ::= remove(.path = path_ptr)
    still_exists ::= exists(.self = self, .path = path)
    if still_exists {
        ok = 0 == 1
        return
    }
    ok = 1 == 1
}

remove(
    .self: &FileSystem,
    .path: &String,
) -> (.ok: Bool) := {
    c_path ::= as_c_string(.self = path)
    ok = remove(.self = self, .path = c_path).ok
}

remove(
    .self: &FileSystem,
    .path: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.ok: Bool) := {
    c_path ::= as_c_string(.self = path, .allocator = allocator)
    ok = remove(.self = self, .path = c_path.text).ok
}

rename(
    .self: &FileSystem,
    .from: CString,
    .to: CString,
) -> (.ok: Bool) := {
    from_ptr ::= pointer(.self = &from)
    to_ptr ::= pointer(.self = &to)
    _ ::= rename(.old_path = from_ptr, .new_path = to_ptr)
    from_exists ::= exists(.self = self, .path = from)
    to_exists ::= exists(.self = self, .path = to)
    if from_exists {
        ok = 0 == 1
        return
    }
    ok = to_exists
}

rename(
    .self: &FileSystem,
    .from: &String,
    .to: &String,
) -> (.ok: Bool) := {
    c_from ::= as_c_string(.self = from)
    c_to ::= as_c_string(.self = to)
    ok = rename(.self = self, .from = c_from, .to = c_to).ok
}

rename(
    .self: &FileSystem,
    .from: StringView,
    .to: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.ok: Bool) := {
    c_from ::= as_c_string(.self = from, .allocator = allocator)
    c_to ::= as_c_string(.self = to, .allocator = allocator)
    ok = rename(.self = self, .from = c_from.text, .to = c_to.text).ok
}


open_read(
    .self: &FileSystem,
    .path: CString,
) -> (.file: File) := {
    file = File(.handle = 0, .should_close = 0 == 1)
    open_read(.p = $&file, .path = path)
}

open_read(
    .self: &FileSystem,
    .path: &String,
) -> (.file: File) := {
    c_path ::= as_c_string(.self = path)
    file = open_read(.self = self, .path = c_path)
}

open_read(
    .self: &FileSystem,
    .path: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.file: File) := {
    c_path ::= as_c_string(.self = path, .allocator = allocator)
    file = open_read(.self = self, .path = c_path.text)
}

open_write(
    .self: &FileSystem,
    .path: CString,
) -> (.file: File) := {
    file = File(.handle = 0, .should_close = 0 == 1)
    open_write(.p = $&file, .path = path)
}

open_write(
    .self: &FileSystem,
    .path: &String,
) -> (.file: File) := {
    c_path ::= as_c_string(.self = path)
    file = open_write(.self = self, .path = c_path)
}

open_write(
    .self: &FileSystem,
    .path: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.file: File) := {
    c_path ::= as_c_string(.self = path, .allocator = allocator)
    file = open_write(.self = self, .path = c_path.text)
}

open_append(
    .self: &FileSystem,
    .path: CString,
) -> (.file: File) := {
    file = File(.handle = 0, .should_close = 0 == 1)
    open_append(.p = $&file, .path = path)
}

open_append(
    .self: &FileSystem,
    .path: &String,
) -> (.file: File) := {
    c_path ::= as_c_string(.self = path)
    file = open_append(.self = self, .path = c_path)
}

open_append(
    .self: &FileSystem,
    .path: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.file: File) := {
    c_path ::= as_c_string(.self = path, .allocator = allocator)
    file = open_append(.self = self, .path = c_path.text)
}

read_file(
    .self: &FileSystem,
    .path: CString,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.text: String) := {
    file ::= open_read(.self = self, .path = path)

    initial_capacity :: UIntNative = 16
    zero :: UIntNative = 0
    capacity :: UIntNative = initial_capacity
    buffer :: $&UInt8 = allocate(.self = allocator, .size = capacity)
    length :: UIntNative = zero

    while 1 == 1 {
        next ::= read_byte(.self = $&file)
        if is(.value = next, .variant = ..end) {
            break
        }

        if length == capacity {
            new_capacity :: UIntNative = capacity * 2
            new_buffer : $&UInt8 = allocate(.self = allocator, .size = new_capacity)
            memcpy(
                .dst = cast#(.to: $&Any)(.value = cast#(.to: UIntNative)(.value = new_buffer)),
                .src = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = buffer)),
                .n = length,
            )
            deallocate(.self = allocator, .data = buffer, .size = capacity)
            buffer = new_buffer
            capacity = new_capacity
        }

        payload ::= next..ok
        byte_ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = buffer) + length)
        byte_ptr& = payload.byte
        length = length + 1
    }

    text = String(.allocator = allocator, .length = length)
    if length > 0 {
        memcpy(
            .dst = cast#(.to: $&Any)(.value = cast#(.to: UIntNative)(.value = text.allocation.data)),
            .src = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = buffer)),
            .n = length,
        )
    }

    deallocate(.self = allocator, .data = buffer, .size = capacity)
    close(.self = $&file)
}

read_file(
    .self: &FileSystem,
    .path: &String,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.text: String) := {
    c_path ::= as_c_string(.self = path)
    text = read_file(.self = self, .path = c_path, .allocator = allocator)
}

read_file(
    .self: &FileSystem,
    .path: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.text: String) := {
    c_path ::= as_c_string(.self = path, .allocator = allocator)
    text = read_file(.self = self, .path = c_path.text, .allocator = allocator)
}

write_file(
    .self: &FileSystem,
    .path: CString,
    .text: String,
) -> (.ok: Bool) := {
    file ::= open_write(.self = self, .path = path)
    if is_open(.self = &file).ok {
    } else {
        ok = 0 == 1
        return
    }

    write(.self = $&file, .text = text)
    flush(.self = $&file)
    close(.self = $&file)
    ok = 1 == 1
}

write_file(
    .self: &FileSystem,
    .path: &String,
    .text: String,
) -> (.ok: Bool) := {
    c_path ::= as_c_string(.self = path)
    ok = write_file(.self = self, .path = c_path, .text = text).ok
}

write_file(
    .self: &FileSystem,
    .path: StringView,
    .text: String,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.ok: Bool) := {
    c_path ::= as_c_string(.self = path, .allocator = allocator)
    ok = write_file(.self = self, .path = c_path.text, .text = text).ok
}
