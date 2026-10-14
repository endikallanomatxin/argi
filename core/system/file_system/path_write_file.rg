-- Path representation selects one operation identity; allocation is explicit.
FileWriting#(.PathValue: Type): Contract = (
    .Result: Type
    .write_file: (.self: &FileSystem, .path: PathValue, .text: &String) -> (.result: Result)
)

AllocatingFileWriting#(.PathValue: Type, .Provider: Type: Allocator#(Provider)): Contract = (
    .Result: Type
    .write_file: (.self: &FileSystem, .path: PathValue, .text: &String, .allocator: $&Provider = reach allocator) -> (.result: Result)
)

_path_write_file_c := (
        .self : &FileSystem,
        .path : &Char,
        .text : &String,
    ) -> (.result: Errable#(
            Void,
            (
                ..path_open_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..stream_close_failed
            )
        )) {
    assume ffi := self&._ffi
    open_result ::= File(.file_system = self, .path = path, .mode = ..write)
    file :: File

    match open_result {
        ..ok ~payload { file = ~payload }
        ..error _ {
            result = ..error(.reason = ..path_open_failed)
            return
        }
    }

    wrote ::= write($&file, .value = text)

    match wrote {
        ..ok _ {
        }
        ..error&err {
            _ ::= close($&file)
            if is(.value = err&.reason, .variant = ..stream_write_failed) {
                result = ..error(.reason = ..stream_write_failed)
            } else {
                result = ..error(.reason = ..stream_flush_failed)
            }
            return
        }
    }

    flushed ::= Writer#().flush(.self = $&file)

    match flushed {
        ..ok _ {
        }
        ..error&err {
            _ ::= close($&file)
            if is(.value = err&.reason, .variant = ..stream_write_failed) {
                result = ..error(.reason = ..stream_write_failed)
            } else {
                result = ..error(.reason = ..stream_flush_failed)
            }
            return
        }
    }

    closed ::= close($&file)

    if is(.value = closed, .variant = ..error) {
        result = ..error(.reason = ..stream_close_failed)
        return
    }

    result = ..ok Void()
}


_path_write_file_string := (
        .self : &FileSystem,
        .path : &String,
        .text : &String,
    ) -> (.result: Errable#(
            Void,
            (
                ..path_open_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..stream_close_failed
            )
        )) {
    assume ffi := self&._ffi
    c_path ::= as_c_string(path)

    result = write_file(self, .path = c_path, .text = text)
}


_path_write_file_view#(.Provider: Type: Allocator#(Provider)) := (
        .self      : &FileSystem,
        .path      : StringView,
        .text      : &String,
        .allocator : $&Provider,
    ) -> (.result: Errable#(
            Void,
            (
                ..path_open_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..stream_close_failed,
                ..out_of_memory
            )
        )) {
    assume ffi := self&._ffi
    assume allocator

    converted ::= copy_c_string(path, .allocator = allocator)

    match converted {
        ..ok ~payload {
            written ::= write_file(self, .path = payload.text, .text = text)!
            result = ..ok ~written
        }
        ..error _ { result = ..error(.reason = ..out_of_memory) }
    }
}


_path_write_file_owned := (
        .self      : &FileSystem,
        .path      : &Path,
        .text      : &String,
    ) -> (.result: Errable#(
            Void,
            (
                ..path_open_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..stream_close_failed
            )
        )) {
    assume ffi := self&._ffi

    result = write_file(self, .path = &path&.text, .text = text)
}


implement FileWriting#(&Char) (
    .Result: Type = Errable#(
            Void,
            (
                ..path_open_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..stream_close_failed
            )
        )
    .write_file = _path_write_file_c
)

implement FileWriting#(&String) (
    .Result: Type = Errable#(
            Void,
            (
                ..path_open_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..stream_close_failed
            )
        )
    .write_file = _path_write_file_string
)

implement#(.Provider: Type: Allocator#(Provider)) AllocatingFileWriting#(StringView, Provider) (
    .Result: Type = Errable#(
            Void,
            (
                ..path_open_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..stream_close_failed,
                ..out_of_memory
            )
        )
    .write_file = _path_write_file_view
)

implement FileWriting#(&Path) (
    .Result: Type = Errable#(
            Void,
            (
                ..path_open_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..stream_close_failed
            )
        )
    .write_file = _path_write_file_owned
)

