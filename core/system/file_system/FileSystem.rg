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
) -> (.ok: Bool) := {
    size :: UIntNative = path.length + 1
    raw_buffer : $&Any = malloc(.size = size)
    temp_path : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = raw_buffer))
    i :: UIntNative = 0
    while i < path.length {
        ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_path) + i)
        ptr& = bytes_get(.view = &path, .index = i).byte
        i = i + 1
    }
    nul_ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_path) + path.length)
    nul_ptr& = 0
    c_path : CString = (
        .data = cast#(.to: UIntNative)(.value = temp_path)
    )
    ok = exists(.self = self, .path = c_path).ok
    free(.pointer = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = temp_path)))
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
) -> (.ok: Bool) := {
    size :: UIntNative = path.length + 1
    raw_buffer : $&Any = malloc(.size = size)
    temp_path : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = raw_buffer))
    i :: UIntNative = 0
    while i < path.length {
        ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_path) + i)
        ptr& = bytes_get(.view = &path, .index = i).byte
        i = i + 1
    }
    nul_ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_path) + path.length)
    nul_ptr& = 0
    c_path : CString = (
        .data = cast#(.to: UIntNative)(.value = temp_path)
    )
    ok = remove(.self = self, .path = c_path).ok
    free(.pointer = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = temp_path)))
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
) -> (.ok: Bool) := {
    from_size :: UIntNative = from.length + 1
    from_raw_buffer : $&Any = malloc(.size = from_size)
    temp_from : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = from_raw_buffer))
    from_i :: UIntNative = 0
    while from_i < from.length {
        ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_from) + from_i)
        ptr& = bytes_get(.view = &from, .index = from_i).byte
        from_i = from_i + 1
    }
    from_nul_ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_from) + from.length)
    from_nul_ptr& = 0

    to_size :: UIntNative = to.length + 1
    to_raw_buffer : $&Any = malloc(.size = to_size)
    temp_to : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = to_raw_buffer))
    to_i :: UIntNative = 0
    while to_i < to.length {
        ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_to) + to_i)
        ptr& = bytes_get(.view = &to, .index = to_i).byte
        to_i = to_i + 1
    }
    to_nul_ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_to) + to.length)
    to_nul_ptr& = 0

    c_from : CString = (
        .data = cast#(.to: UIntNative)(.value = temp_from)
    )
    c_to : CString = (
        .data = cast#(.to: UIntNative)(.value = temp_to)
    )
    ok = rename(.self = self, .from = c_from, .to = c_to).ok
    free(.pointer = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = temp_from)))
    free(.pointer = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = temp_to)))
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
) -> (.file: File) := {
    size :: UIntNative = path.length + 1
    raw_buffer : $&Any = malloc(.size = size)
    temp_path : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = raw_buffer))
    i :: UIntNative = 0
    while i < path.length {
        ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_path) + i)
        ptr& = bytes_get(.view = &path, .index = i).byte
        i = i + 1
    }
    nul_ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_path) + path.length)
    nul_ptr& = 0
    c_path : CString = (
        .data = cast#(.to: UIntNative)(.value = temp_path)
    )
    file = open_read(.self = self, .path = c_path)
    free(.pointer = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = temp_path)))
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
) -> (.file: File) := {
    size :: UIntNative = path.length + 1
    raw_buffer : $&Any = malloc(.size = size)
    temp_path : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = raw_buffer))
    i :: UIntNative = 0
    while i < path.length {
        ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_path) + i)
        ptr& = bytes_get(.view = &path, .index = i).byte
        i = i + 1
    }
    nul_ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_path) + path.length)
    nul_ptr& = 0
    c_path : CString = (
        .data = cast#(.to: UIntNative)(.value = temp_path)
    )
    file = open_write(.self = self, .path = c_path)
    free(.pointer = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = temp_path)))
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
) -> (.file: File) := {
    size :: UIntNative = path.length + 1
    raw_buffer : $&Any = malloc(.size = size)
    temp_path : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = raw_buffer))
    i :: UIntNative = 0
    while i < path.length {
        ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_path) + i)
        ptr& = bytes_get(.view = &path, .index = i).byte
        i = i + 1
    }
    nul_ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_path) + path.length)
    nul_ptr& = 0
    c_path : CString = (
        .data = cast#(.to: UIntNative)(.value = temp_path)
    )
    file = open_append(.self = self, .path = c_path)
    free(.pointer = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = temp_path)))
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
    size :: UIntNative = path.length + 1
    raw_buffer : $&Any = malloc(.size = size)
    temp_path : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = raw_buffer))
    i :: UIntNative = 0
    while i < path.length {
        ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_path) + i)
        ptr& = bytes_get(.view = &path, .index = i).byte
        i = i + 1
    }
    nul_ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_path) + path.length)
    nul_ptr& = 0
    c_path : CString = (
        .data = cast#(.to: UIntNative)(.value = temp_path)
    )
    text = read_file(.self = self, .path = c_path, .allocator = allocator)
    free(.pointer = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = temp_path)))
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
) -> (.ok: Bool) := {
    size :: UIntNative = path.length + 1
    raw_buffer : $&Any = malloc(.size = size)
    temp_path : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = raw_buffer))
    i :: UIntNative = 0
    while i < path.length {
        ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_path) + i)
        ptr& = bytes_get(.view = &path, .index = i).byte
        i = i + 1
    }
    nul_ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_path) + path.length)
    nul_ptr& = 0
    c_path : CString = (
        .data = cast#(.to: UIntNative)(.value = temp_path)
    )
    ok = write_file(.self = self, .path = c_path, .text = text).ok
    free(.pointer = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = temp_path)))
}
