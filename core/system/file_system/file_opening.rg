-- Canonical file opening selects path representation and allocation evidence
-- through Init Args. Borrowed terminated paths do not allocate temporary text.
_open_c_file := (.file_system: &FileSystem, .path: &Char, .mode: FileOpenMode) -> (.result: Errable#(File, (..path_open_failed))) {
    assume ffi := file_system&._ffi
    file ::= File(.stream_address = 0, .should_close = false)
    opened ::= open(.p = $&file, .path = path, .mode = mode)
    if is(.value = opened, .variant = ..ok) {
        result = ..ok ~file
        return
    }
    result = ..error(.reason = ..path_open_failed)
}

implement Init#(File, (.file_system: &FileSystem, .path: &Char, .mode: FileOpenMode = ..read)) (
    .Result: Type = Errable#(File, (..path_open_failed))
    .init = (.args: (.file_system: &FileSystem, .path: &Char, .mode: FileOpenMode = ..read)) -> (.result: Result) {
        result = _open_c_file(.file_system = args.file_system, .path = args.path, .mode = args.mode)
    }
)

implement Init#(File, (.file_system: &FileSystem, .path: &String, .mode: FileOpenMode = ..read)) (
    .Result: Type = Errable#(File, (..path_open_failed))
    .init = (.args: (.file_system: &FileSystem, .path: &String, .mode: FileOpenMode = ..read)) -> (.result: Result) {
        result = _open_c_file(.file_system = args.file_system, .path = as_c_string(args.path), .mode = args.mode)
    }
)

implement Init#(File, (.file_system: &FileSystem, .path: &Path, .mode: FileOpenMode = ..read)) (
    .Result: Type = Errable#(File, (..path_open_failed))
    .init = (.args: (.file_system: &FileSystem, .path: &Path, .mode: FileOpenMode = ..read)) -> (.result: Result) {
        result = _open_c_file(.file_system = args.file_system, .path = as_c_string(&args.path&.text), .mode = args.mode)
    }
)

implement#(.Provider: Type: Allocator#(Provider)) Init#(File, (.file_system: &FileSystem, .path: StringView, .mode: FileOpenMode = ..read, .allocator: $&Provider = reach allocator)) (
    .Result: Type = Errable#(File, (..path_open_failed, ..out_of_memory))
    .init = (.args: (.file_system: &FileSystem, .path: StringView, .mode: FileOpenMode = ..read, .allocator: $&Provider = reach allocator)) -> (.result: Result) {
        assume ffi := args.file_system&._ffi
        assume allocator := args.allocator
        converted ::= copy_c_string(args.path, .allocator = allocator)
        match converted {
            ..ok ~payload {
                match _open_c_file(.file_system = args.file_system, .path = payload.text, .mode = args.mode) {
                    ..ok ~file { result = ..ok ~file }
                    ..error _ { result = ..error(.reason = ..path_open_failed) }
                }
            }
            ..error _ { result = ..error(.reason = ..out_of_memory) }
        }
    }
)
