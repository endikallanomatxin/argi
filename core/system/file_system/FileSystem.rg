FileSystem : Type = ()

once init(.p: $&FileSystem) -> () := {
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
