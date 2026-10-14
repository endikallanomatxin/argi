-- Path representation selects one operation identity; allocation is explicit.
PathRenaming#(.PathValue: Type): Contract = (
    .Result: Type
    .rename: (.self: &FileSystem, .from: PathValue, .to: PathValue) -> (.result: Result)
)

AllocatingPathRenaming#(.PathValue: Type, .Provider: Type: Allocator#(Provider)): Contract = (
    .Result: Type
    .rename: (.self: &FileSystem, .from: PathValue, .to: PathValue, .allocator: $&Provider = reach allocator) -> (.result: Result)
)

_path_rename_c := (
        .self : &FileSystem,
        .from : &Char,
        .to   : &Char,
    ) -> (.result: Errable#(Bool, (..path_rename_failed))) {
    assume ffi := self&._ffi

    if rename(.old_path = from, .new_path = to).status != 0 {
        result = ..error(.reason = ..path_rename_failed)
        return
    }

    result = ..ok 1 == 1
}


_path_rename_string := (
        .self : &FileSystem,
        .from : &String,
        .to   : &String,
    ) -> (.result: Errable#(Bool, (..path_rename_failed))) {
    assume ffi := self&._ffi
    c_from ::= as_c_string(from)
    c_to ::= as_c_string(to)

    result = rename(.self = self, .from = c_from, .to = c_to)
}


_path_rename_view#(.Provider: Type: Allocator#(Provider)) := (
        .self      : &FileSystem,
        .from      : StringView,
        .to        : StringView,
        .allocator : $&Provider,
    ) -> (.result: Errable#(Bool, (..path_rename_failed, ..out_of_memory))) {
    assume ffi := self&._ffi
    assume allocator

    converted_from ::= copy_c_string(from, .allocator = allocator)

    match converted_from {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~from_payload {
            converted_to ::= copy_c_string(to, .allocator = allocator)
            match converted_to {
                ..ok ~to_payload {
                    renamed ::= rename(.self = self, .from = from_payload.text, .to = to_payload.text)!
                    result = ..ok renamed
                }
                ..error _ { result = ..error(.reason = ..out_of_memory) }
            }
        }
    }
}


_path_rename_owned := (
        .self      : &FileSystem,
        .from      : &Path,
        .to        : &Path,
    ) -> (.result: Errable#(Bool, (..path_rename_failed))) {
    assume ffi := self&._ffi

    result = rename(.self = self, .from = &from&.text, .to = &to&.text)
}


implement PathRenaming#(&Char) (
    .Result: Type = Errable#(Bool, (..path_rename_failed))
    .rename = _path_rename_c
)

implement PathRenaming#(&String) (
    .Result: Type = Errable#(Bool, (..path_rename_failed))
    .rename = _path_rename_string
)

implement#(.Provider: Type: Allocator#(Provider)) AllocatingPathRenaming#(StringView, Provider) (
    .Result: Type = Errable#(Bool, (..path_rename_failed, ..out_of_memory))
    .rename = _path_rename_view
)

implement PathRenaming#(&Path) (
    .Result: Type = Errable#(Bool, (..path_rename_failed))
    .rename = _path_rename_owned
)

