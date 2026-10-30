-- Path representation selects one operation identity; allocation is explicit.
PathExistence#(.PathValue: Type): Contract = (
    .Result : Type
    .exists : (.self: &FileSystem, .path: PathValue) -> (.ok: Result)
)

AllocatingPathExistence#(.PathValue: Type, .Provider: Type: Allocator#(Provider)): Contract = (
    .Result : Type
    .exists : (.self: &FileSystem, .path: PathValue, .allocator: $&Provider) -> (.result: Result)
)

_path_exists_c := (.self: &FileSystem, .path: &CChar) -> (.ok: Bool) {
    assume ffi := self&._ffi
    ok = access(.path = path, .mode = 0).status == 0
}

_path_exists_string := (.self: &FileSystem, .path: &String) -> (.ok: Bool) {
    assume ffi := self&._ffi
    c_path ::= as_c_string(path)
    ok = exists(self, .path = c_path).ok
}

_path_exists_view := #(.Provider: Type: Allocator#(Provider)) (
    .self: &FileSystem, .path: StringView, .allocator: $&Provider
) -> (.result: Errable#(Bool, (..out_of_memory))) {

    assume ffi := self&._ffi
    assume allocator

    converted ::= copy_c_string(path, .allocator = allocator)

    match converted {
        ..ok ~payload { result = ..ok exists(self, .path = payload.text).ok }
        ..error _ { result = ..error(.reason = ..out_of_memory) }
    }
}

_path_exists_owned := (.self: &FileSystem, .path: &Path) -> (.ok: Bool) {
    assume ffi := self&._ffi
    ok = exists(self, .path = &path&.text).ok
}

implement PathExistence#(&CChar) (
    .Result : Type = Bool
    .exists = _path_exists_c
)

implement PathExistence#(&String) (
    .Result : Type = Bool
    .exists = _path_exists_string
)

implement#(.Provider: Type: Allocator#(Provider)) AllocatingPathExistence#(StringView, Provider) (
    .Result : Type = Errable#(Bool, (..out_of_memory))
    .exists = _path_exists_view
)

implement PathExistence#(&Path) (
    .Result : Type = Bool
    .exists = _path_exists_owned
)
