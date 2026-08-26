FileSystem : Type = ()
..path_open_failed
..path_remove_failed
..path_rename_failed

once init(.p: $&FileSystem) -> () := {
}

exists(
    .self: &FileSystem,
    .path: &Char,
) -> (.ok: Bool) := {
    ok = access(.path = path, .mode = 0).status == 0
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
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Bool, .reasons: (..out_of_memory))) := {
    converted ::= as_c_string(.self = path, .allocator = allocator)
    match converted {
        ..ok ~ payload { result = ..ok exists(.self = self, .path = payload.text).ok }
        ..error _ { result = ..error(.reason = ..out_of_memory) }
    }
}

exists(
    .self: &FileSystem,
    .path: &Path,
) -> (.ok: Bool) := {
    ok = exists(.self = self, .path = &path&.text).ok
}

remove(
    .self: &FileSystem,
    .path: &Char,
) -> (.result: Errable#(.t: Bool, .reasons: (..path_remove_failed))) := {
    if remove(.path = path).status != 0 {
        result = ..error(.reason = ..path_remove_failed)
        return
    }
    result = ..ok 1 == 1
}

remove(
    .self: &FileSystem,
    .path: &String,
) -> (.result: Errable#(.t: Bool, .reasons: (..path_remove_failed))) := {
    c_path ::= as_c_string(.self = path)
    result = remove(.self = self, .path = c_path)
}

remove(
    .self: &FileSystem,
    .path: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Bool, .reasons: (..path_remove_failed, ..out_of_memory))) := {
    converted ::= as_c_string(.self = path, .allocator = allocator)
    match converted {
        ..ok ~ payload { result = remove(.self = self, .path = payload.text) }
        ..error _ { result = ..error(.reason = ..out_of_memory) }
    }
}

remove(
    .self: &FileSystem,
    .path: &Path,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Bool, .reasons: (..path_remove_failed))) := {
    result = remove(.self = self, .path = &path&.text)
}

rename(
    .self: &FileSystem,
    .from: &Char,
    .to: &Char,
) -> (.result: Errable#(.t: Bool, .reasons: (..path_rename_failed))) := {
    if rename(.old_path = from, .new_path = to).status != 0 {
        result = ..error(.reason = ..path_rename_failed)
        return
    }
    result = ..ok 1 == 1
}

rename(
    .self: &FileSystem,
    .from: &String,
    .to: &String,
) -> (.result: Errable#(.t: Bool, .reasons: (..path_rename_failed))) := {
    c_from ::= as_c_string(.self = from)
    c_to ::= as_c_string(.self = to)
    result = rename(.self = self, .from = c_from, .to = c_to)
}

rename(
    .self: &FileSystem,
    .from: StringView,
    .to: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Bool, .reasons: (..path_rename_failed, ..out_of_memory))) := {
    converted_from ::= as_c_string(.self = from, .allocator = allocator)
    match converted_from {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~ from_payload {
            converted_to ::= as_c_string(.self = to, .allocator = allocator)
            match converted_to {
                ..ok ~ to_payload { result = rename(.self = self, .from = from_payload.text, .to = to_payload.text) }
                ..error _ { result = ..error(.reason = ..out_of_memory) }
            }
        }
    }
}

rename(
    .self: &FileSystem,
    .from: &Path,
    .to: &Path,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Bool, .reasons: (..path_rename_failed))) := {
    result = rename(.self = self, .from = &from&.text, .to = &to&.text)
}


open_read(
    .self: &FileSystem,
    .path: &Char,
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed))) := {
    file :: File = File(.stream_address = 0, .should_close = 0 == 1)
    opened ::= open_read(.p = $&file, .path = path)
    if is(.value = opened, .variant = ..ok) {
        result = ..ok ~file
        return
    }
    result = ..error(.reason = ..path_open_failed)
}

open_read(
    .self: &FileSystem,
    .path: &String,
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed))) := {
    c_path ::= as_c_string(.self = path)
    result = open_read(.self = self, .path = c_path)
}

open_read(
    .self: &FileSystem,
    .path: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed, ..out_of_memory))) := {
    converted ::= as_c_string(.self = path, .allocator = allocator)
    match converted {
        ..ok ~ payload { result = open_read(.self = self, .path = payload.text) }
        ..error _ { result = ..error(.reason = ..out_of_memory) }
    }
}

open_read(
    .self: &FileSystem,
    .path: &Path,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed))) := {
    result = open_read(.self = self, .path = &path&.text)
}

open_write(
    .self: &FileSystem,
    .path: &Char,
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed))) := {
    file :: File = File(.stream_address = 0, .should_close = 0 == 1)
    opened ::= open_write(.p = $&file, .path = path)
    if is(.value = opened, .variant = ..ok) {
        result = ..ok ~file
        return
    }
    result = ..error(.reason = ..path_open_failed)
}

open_write(
    .self: &FileSystem,
    .path: &String,
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed))) := {
    c_path ::= as_c_string(.self = path)
    result = open_write(.self = self, .path = c_path)
}

open_write(
    .self: &FileSystem,
    .path: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed, ..out_of_memory))) := {
    converted ::= as_c_string(.self = path, .allocator = allocator)
    match converted {
        ..ok ~ payload { result = open_write(.self = self, .path = payload.text) }
        ..error _ { result = ..error(.reason = ..out_of_memory) }
    }
}

open_write(
    .self: &FileSystem,
    .path: &Path,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed))) := {
    result = open_write(.self = self, .path = &path&.text)
}

open_append(
    .self: &FileSystem,
    .path: &Char,
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed))) := {
    file :: File = File(.stream_address = 0, .should_close = 0 == 1)
    opened ::= open_append(.p = $&file, .path = path)
    if is(.value = opened, .variant = ..ok) {
        result = ..ok ~file
        return
    }
    result = ..error(.reason = ..path_open_failed)
}

open_append(
    .self: &FileSystem,
    .path: &String,
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed))) := {
    c_path ::= as_c_string(.self = path)
    result = open_append(.self = self, .path = c_path)
}

open_append(
    .self: &FileSystem,
    .path: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed, ..out_of_memory))) := {
    converted ::= as_c_string(.self = path, .allocator = allocator)
    match converted {
        ..ok ~ payload { result = open_append(.self = self, .path = payload.text) }
        ..error _ { result = ..error(.reason = ..out_of_memory) }
    }
}

open_append(
    .self: &FileSystem,
    .path: &Path,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed))) := {
    result = open_append(.self = self, .path = &path&.text)
}

read_file(
    .self: &FileSystem,
    .path: &Char,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: String, .reasons: (..path_open_failed, ..stream_read_failed, ..stream_close_failed, ..out_of_memory))) := {
    open_result ::= open_read(.self = self, .path = path)
    file :: File
    match open_result {
        ..ok ~ payload { file = ~payload }
        ..error _ {
            result = ..error(.reason = ..path_open_failed)
            return
        }
    }

    create_result ::= string_with_capacity(.allocator = allocator, .capacity = 16)
    text :: String
    match create_result {
        ..ok ~ payload { text = ~payload }
        ..error _ {
            _ ::= close(.self = $&file)
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }

    while 1 == 1 {
        next ::= read_byte(.self = $&file)
        if is(.value = next, .variant = ..error) {
            deinit(.self = $&text)
            _ ::= close(.self = $&file)
            result = ..error(.reason = ..stream_read_failed)
            return
        }

        next_value ::= next..ok
        if is(.value = next_value, .variant = ..end) {
            break
        }

        payload ::= next_value..ok
        grew ::= push_byte(.self = $&text, .byte = payload, .allocator = allocator)
        match grew {
            ..ok _ {
            }
            ..error _ {
                deinit(.self = $&text)
                _ ::= close(.self = $&file)
                result = ..error(.reason = ..out_of_memory)
                return
            }
        }
    }

    close_result ::= close(.self = $&file)
    if is(.value = close_result, .variant = ..error) {
        deinit(.self = $&text)
        result = ..error(.reason = ..stream_close_failed)
        return
    }
    result = ..ok ~text
}

read_file(
    .self: &FileSystem,
    .path: &String,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: String, .reasons: (..path_open_failed, ..stream_read_failed, ..stream_close_failed, ..out_of_memory))) := {
    c_path ::= as_c_string(.self = path)
    result = read_file(.self = self, .path = c_path, .allocator = allocator)
}

read_file(
    .self: &FileSystem,
    .path: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: String, .reasons: (..path_open_failed, ..stream_read_failed, ..stream_close_failed, ..out_of_memory))) := {
    converted ::= as_c_string(.self = path, .allocator = allocator)
    match converted {
        ..ok ~ payload { result = read_file(.self = self, .path = payload.text, .allocator = allocator) }
        ..error _ { result = ..error(.reason = ..out_of_memory) }
    }
}

read_file(
    .self: &FileSystem,
    .path: &Path,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: String, .reasons: (..path_open_failed, ..stream_read_failed, ..stream_close_failed, ..out_of_memory))) := {
    result = read_file(.self = self, .path = &path&.text, .allocator = allocator)
}

write_file(
    .self: &FileSystem,
    .path: &Char,
    .text: &String,
) -> (.result: Errable#(.t: Void, .reasons: (..path_open_failed, ..stream_write_failed, ..stream_flush_failed, ..stream_close_failed))) := {
    open_result ::= open_write(.self = self, .path = path)
    file :: File
    match open_result {
        ..ok ~ payload { file = ~payload }
        ..error _ {
            result = ..error(.reason = ..path_open_failed)
            return
        }
    }

    wrote ::= write(.self = $&file, .text = text)
    match wrote {
        ..ok _ {
        }
        ..error & err {
            _ ::= close(.self = $&file)
            if is(.value = err&.reason, .variant = ..stream_write_failed) {
                result = ..error(.reason = ..stream_write_failed)
            } else {
                result = ..error(.reason = ..stream_flush_failed)
            }
            return
        }
    }

    flushed ::= flush(.self = $&file)
    match flushed {
        ..ok _ {
        }
        ..error & err {
            _ ::= close(.self = $&file)
            if is(.value = err&.reason, .variant = ..stream_write_failed) {
                result = ..error(.reason = ..stream_write_failed)
            } else {
                result = ..error(.reason = ..stream_flush_failed)
            }
            return
        }
    }

    closed ::= close(.self = $&file)
    if is(.value = closed, .variant = ..error) {
        result = ..error(.reason = ..stream_close_failed)
        return
    }

    result = ..ok Void()
}

write_file(
    .self: &FileSystem,
    .path: &String,
    .text: &String,
) -> (.result: Errable#(.t: Void, .reasons: (..path_open_failed, ..stream_write_failed, ..stream_flush_failed, ..stream_close_failed))) := {
    c_path ::= as_c_string(.self = path)
    result = write_file(.self = self, .path = c_path, .text = text)
}

write_file(
    .self: &FileSystem,
    .path: StringView,
    .text: &String,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..path_open_failed, ..stream_write_failed, ..stream_flush_failed, ..stream_close_failed, ..out_of_memory))) := {
    converted ::= as_c_string(.self = path, .allocator = allocator)
    match converted {
        ..ok ~ payload { result = write_file(.self = self, .path = payload.text, .text = text) }
        ..error _ { result = ..error(.reason = ..out_of_memory) }
    }
}

write_file(
    .self: &FileSystem,
    .path: &Path,
    .text: &String,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..path_open_failed, ..stream_write_failed, ..stream_flush_failed, ..stream_close_failed))) := {
    result = write_file(.self = self, .path = &path&.text, .text = text)
}
