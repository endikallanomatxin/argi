_FileSystemInitArgs: Type = (.ffi: $&ForeignFunctionInterface = reach ffi)

FileSystem: Type = (._ffi: $&ForeignFunctionInterface)

..path_open_failed
..path_remove_failed
..path_rename_failed

once _acquire_file_system := (.args: _FileSystemInitArgs) -> (.result: FileSystem) {
    ffi ::= args.ffi

    result._ffi = ffi
}

implement Init#(FileSystem, _FileSystemInitArgs) (
    .Result : Type = FileSystem
    .init   = _acquire_file_system
)

_read_c_file#(.Provider: Type: Allocator#(Provider)) := (
    .self: &FileSystem, .path: &CChar, .allocator: $&Provider
) -> (
    .result : Errable#(
        String,
        (
            ..path_open_failed,
            ..stream_read_failed,
            ..invalid_utf8,
            ..stream_close_failed,
            ..out_of_memory
        )
    )
) {
    assume ffi := self&._ffi
    assume allocator

    open_result ::= _open_c_file(.file_system = self, .path = path, .mode = ..read)
    file :: File

    match open_result {
        ..ok ~payload { file = ~payload }
        ..error _ {
            result = ..error(.reason = ..path_open_failed)
            return
        }
    }

    create_result ::= string_with_capacity(.allocator = allocator, .capacity = 16)
    text :: String

    match create_result {
        ..ok ~payload { text = ~payload }
        ..error _ {
            _ ::= close($&file)
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }

    while 1 == 1 {
        next ::= Reader#().read_byte($&file)
        if is(.value = next, .variant = ..error) {
            deinit(.self = $&text)
            _ ::= close($&file)
            result = ..error(.reason = ..stream_read_failed)
            return
        }

        next_value ::= next ..ok
        if is(.value = next_value, .variant = ..end) {
            break
        }

        payload ::= next_value ..ok
        grew ::= _string_push_byte($&text, .byte = payload, .allocator = allocator)
        match grew {
            ..ok _ {
            }
            ..error _ {
                deinit(.self = $&text)
                _ ::= close($&file)
                result = ..error(.reason = ..out_of_memory)
                return
            }
        }
    }

    close_result ::= close($&file)

    if is(.value = close_result, .variant = ..error) {
        deinit(.self = $&text)
        result = ..error(.reason = ..stream_close_failed)
        return
    }

    _ ::= _validate_string(.self = &text)!
    result = ..ok ~text
}

_read_string_file#(.Provider: Type: Allocator#(Provider)) := (
    .self: &FileSystem, .path: &String, .allocator: $&Provider
) -> (
    .result : Errable#(
        String,
        (
            ..path_open_failed,
            ..stream_read_failed,
            ..invalid_utf8,
            ..stream_close_failed,
            ..out_of_memory
        )
    )
) {
    assume ffi := self&._ffi
    assume allocator

    c_path ::= as_c_string(path)

    result = read_file(self, .path = c_path, .allocator = allocator)
}

_read_view_file#(.Provider: Type: Allocator#(Provider)) := (
    .self: &FileSystem, .path: StringView, .allocator: $&Provider
) -> (
    .result : Errable#(
        String,
        (
            ..path_open_failed,
            ..stream_read_failed,
            ..invalid_utf8,
            ..stream_close_failed,
            ..out_of_memory
        )
    )
) {
    assume ffi := self&._ffi
    assume allocator

    converted ::= copy_c_string(path, .allocator = allocator)

    match converted {
        ..ok ~payload {
            result = read_file(self, .path = payload.text, .allocator = allocator)
        }
        ..error _ { result = ..error(.reason = ..out_of_memory) }
    }
}

_read_path_file#(.Provider: Type: Allocator#(Provider)) := (
    .self: &FileSystem, .path: &Path, .allocator: $&Provider
) -> (
    .result : Errable#(
        String,
        (
            ..path_open_failed,
            ..stream_read_failed,
            ..invalid_utf8,
            ..stream_close_failed,
            ..out_of_memory
        )
    )
) {
    assume ffi := self&._ffi
    assume allocator

    result = read_file(self, .path = &path&.text, .allocator = allocator)
}
