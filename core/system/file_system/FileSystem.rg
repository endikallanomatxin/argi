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
