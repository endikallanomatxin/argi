-- Path representation selects one operation identity; allocation is explicit.
PathRemoval#(.PathValue: Type): Contract = (
    .Result : Type
    .remove : (.self: &FileSystem, .path: PathValue) -> (.result: Result)
)

AllocatingPathRemoval#(.PathValue: Type, .Provider: Type: Allocator#(Provider)): Contract = (
    .Result : Type
    .remove : (.self: &FileSystem, .path: PathValue, .allocator: $&Provider = reach allocator) -> (
        .result : Result
    )
)

_path_remove_c := (.self: &FileSystem, .path: &Char) -> (
    .result : Errable#(Bool, (..path_remove_failed))
) {
    assume ffi := self&._ffi

    if remove(.path = path).status != 0 {
        result = ..error(.reason = ..path_remove_failed)
        return
    }

    result = ..ok 1 == 1
}

_path_remove_string := (.self: &FileSystem, .path: &String) -> (
    .result : Errable#(Bool, (..path_remove_failed))
) {
    assume ffi := self&._ffi
    c_path ::= as_c_string(path)

    result = remove(.self = self, .path = c_path)
}

_path_remove_view#(.Provider: Type: Allocator#(Provider)) := (
    .self: &FileSystem, .path: StringView, .allocator: $&Provider
) -> (.result: Errable#(Bool, (..path_remove_failed, ..out_of_memory))) {
    assume ffi := self&._ffi
    assume allocator

    converted ::= copy_c_string(path, .allocator = allocator)

    match converted {
        ..ok ~payload {
            match remove(.self = self, .path = payload.text) {
                ..ok removed { result = ..ok removed }
                ..error _ { result = ..error(.reason = ..path_remove_failed) }
            }
        }
        ..error _ { result = ..error(.reason = ..out_of_memory) }
    }
}

_path_remove_owned := (.self: &FileSystem, .path: &Path) -> (
    .result : Errable#(Bool, (..path_remove_failed))
) {
    assume ffi := self&._ffi

    result = remove(.self = self, .path = &path&.text)
}

implement PathRemoval#(&Char) (
    .Result : Type = Errable#(Bool, (..path_remove_failed))
    .remove = _path_remove_c
)

implement PathRemoval#(&String) (
    .Result : Type = Errable#(Bool, (..path_remove_failed))
    .remove = _path_remove_string
)

implement#(.Provider: Type: Allocator#(Provider)) AllocatingPathRemoval#(StringView, Provider) (
    .Result : Type = Errable#(Bool, (..path_remove_failed, ..out_of_memory))
    .remove = _path_remove_view
)

implement PathRemoval#(&Path) (
    .Result : Type = Errable#(Bool, (..path_remove_failed))
    .remove = _path_remove_owned
)
