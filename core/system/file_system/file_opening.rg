-- Opening is a fallible factory; Init retains the canonical empty file handle.
FileOpening#(.PathValue: Type): Contract = (
    .open_file : (
        .file_system  : &FileSystem,
        .path         : PathValue,
        .mode         : FileOpenMode            = ..read,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(File, (..path_open_failed)))
)

AllocatingFileOpening#(.PathValue: Type, .Provider: Type: Allocator#(Provider)): Contract = (
    .open_file : (
        .file_system  : &FileSystem,
        .path         : PathValue,
        .mode         : FileOpenMode            = ..read,
        .allocator    : $&Provider,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(File, (..path_open_failed, ..out_of_memory)))
)

_open_c_file := (
    .file_system  : &FileSystem,
    .path         : &CChar,
    .mode         : FileOpenMode,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(File, (..path_open_failed))) {
    assume error_tracer

    assume ffi := file_system&._ffi
    file ::= File()
    opened ::= open(.p = $&file, .path = path, .mode = mode)
    if is(.value = opened, .variant = ..ok) {
        result = ..ok ~file
        return
    }
    result = ..error(.reason = ..path_open_failed)
}

implement FileOpening#(&CChar) (
    .open_file = (
        .file_system  : &FileSystem,
        .path         : &CChar,
        .mode         : FileOpenMode            = ..read,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(File, (..path_open_failed))) {
        assume error_tracer

        result = _open_c_file(.file_system = file_system, .path = path, .mode = mode)
    }
)

implement FileOpening#(&String) (
    .open_file = (
        .file_system  : &FileSystem,
        .path         : &String,
        .mode         : FileOpenMode            = ..read,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(File, (..path_open_failed))) {
        assume error_tracer

        result = _open_c_file(
            .file_system = file_system, .path = as_c_string(path), .mode = mode
        )
    }
)

implement FileOpening#(&Path) (
    .open_file = (
        .file_system  : &FileSystem,
        .path         : &Path,
        .mode         : FileOpenMode            = ..read,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(File, (..path_open_failed))) {
        assume error_tracer

        result = _open_c_file(
            .file_system = file_system, .path = as_c_string(&path&.text), .mode = mode
        )
    }
)

implement#(.Provider: Type: Allocator#(Provider)) AllocatingFileOpening#(StringView, Provider) (
    .open_file = (
        .file_system  : &FileSystem,
        .path         : StringView,
        .mode         : FileOpenMode            = ..read,
        .allocator    : $&Provider,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(File, (..path_open_failed, ..out_of_memory))) {
        assume error_tracer

        assume ffi := file_system&._ffi
        assume allocator
        converted ::= copy_c_string(path, .allocator = allocator)
        match converted {
            ..ok ~payload {
                match _open_c_file(
                    .file_system = file_system, .path = payload.text, .mode = mode
                ) {
                    ..ok ~file { result = ..ok ~file }
                    ..error _ { result = ..error(.reason = ..path_open_failed) }
                }
            }
            ..error _ { result = ..error(.reason = ..out_of_memory) }
        }
    }
)
