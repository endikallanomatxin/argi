FileSystem : Type = ()
..path_open_failed
..path_remove_failed
..path_rename_failed

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
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.ok: Bool) := {
    c_path ::= as_c_string(.self = path, .allocator = allocator)
    ok = exists(.self = self, .path = c_path.text).ok
}

exists(
    .self: &FileSystem,
    .path: &Path,
) -> (.ok: Bool) := {
    ok = exists(.self = self, .path = &path&.text).ok
}

remove(
    .self: &FileSystem,
    .path: CString,
) -> (.result: Errable#(.t: Bool, .reasons: (..path_remove_failed))) := {
    path_ptr ::= pointer(.self = &path)
    if remove(.path = path_ptr).status != 0 {
        result = ..error(.reason = ..path_remove_failed)
        return
    }
    result = ..ok(.value = 1 == 1)
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
) -> (.result: Errable#(.t: Bool, .reasons: (..path_remove_failed))) := {
    c_path ::= as_c_string(.self = path, .allocator = allocator)
    result = remove(.self = self, .path = c_path.text)
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
    .from: CString,
    .to: CString,
) -> (.result: Errable#(.t: Bool, .reasons: (..path_rename_failed))) := {
    from_ptr ::= pointer(.self = &from)
    to_ptr ::= pointer(.self = &to)
    if rename(.old_path = from_ptr, .new_path = to_ptr).status != 0 {
        result = ..error(.reason = ..path_rename_failed)
        return
    }
    result = ..ok(.value = 1 == 1)
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
) -> (.result: Errable#(.t: Bool, .reasons: (..path_rename_failed))) := {
    c_from ::= as_c_string(.self = from, .allocator = allocator)
    c_to ::= as_c_string(.self = to, .allocator = allocator)
    result = rename(.self = self, .from = c_from.text, .to = c_to.text)
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
    .path: CString,
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed))) := {
    file :: File = File(.handle = 0, .should_close = 0 == 1)
    opened ::= open_read(.p = $&file, .path = path)
    if is(.value = opened, .variant = ..ok) {
        result = ..ok(.value = file)
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
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed))) := {
    c_path ::= as_c_string(.self = path, .allocator = allocator)
    result = open_read(.self = self, .path = c_path.text)
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
    .path: CString,
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed))) := {
    file :: File = File(.handle = 0, .should_close = 0 == 1)
    opened ::= open_write(.p = $&file, .path = path)
    if is(.value = opened, .variant = ..ok) {
        result = ..ok(.value = file)
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
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed))) := {
    c_path ::= as_c_string(.self = path, .allocator = allocator)
    result = open_write(.self = self, .path = c_path.text)
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
    .path: CString,
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed))) := {
    file :: File = File(.handle = 0, .should_close = 0 == 1)
    opened ::= open_append(.p = $&file, .path = path)
    if is(.value = opened, .variant = ..ok) {
        result = ..ok(.value = file)
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
) -> (.result: Errable#(.t: File, .reasons: (..path_open_failed))) := {
    c_path ::= as_c_string(.self = path, .allocator = allocator)
    result = open_append(.self = self, .path = c_path.text)
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
    .path: CString,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: String, .reasons: (..path_open_failed, ..stream_read_failed, ..stream_close_failed, ..out_of_memory))) := {
    open_result ::= open_read(.self = self, .path = path)
    if is(.value = open_result, .variant = ..error) {
        result = ..error(.reason = ..path_open_failed)
        return
    }
    file ::= open_result..ok.value

    create_result ::= string_with_capacity(.allocator = allocator, .capacity = 16)
    if is(.value = create_result, .variant = ..error) {
        _ ::= close(.self = $&file)
        result = ..error(.reason = ..out_of_memory)
        return
    }
    text ::= create_result..ok.value

    while 1 == 1 {
        next ::= read_byte(.self = $&file)
        if is(.value = next, .variant = ..error) {
            deallocate(.self = allocator, .data = text.allocation.data, .size = text.allocation.size)
            _ ::= close(.self = $&file)
            result = ..error(.reason = ..stream_read_failed)
            return
        }

        next_value ::= next..ok.value
        if is(.value = next_value, .variant = ..end) {
            break
        }

        payload ::= next_value..ok
        grew ::= push_byte_growing(.self = $&text, .byte = payload.byte, .allocator = allocator)
        match grew {
            ..ok _ {
            }
            ..error _ {
                deallocate(.self = allocator, .data = text.allocation.data, .size = text.allocation.size)
                _ ::= close(.self = $&file)
                result = ..error(.reason = ..out_of_memory)
                return
            }
        }
    }

    close_result ::= close(.self = $&file)
    if is(.value = close_result, .variant = ..error) {
        deallocate(.self = allocator, .data = text.allocation.data, .size = text.allocation.size)
        result = ..error(.reason = ..stream_close_failed)
        return
    }
    result = ..ok(.value = text)
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
    c_path ::= as_c_string(.self = path, .allocator = allocator)
    result = read_file(.self = self, .path = c_path.text, .allocator = allocator)
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
    .path: CString,
    .text: String,
) -> (.result: Errable#(.t: Void, .reasons: (..path_open_failed, ..stream_write_failed, ..stream_flush_failed, ..stream_close_failed))) := {
    open_result ::= open_write(.self = self, .path = path)
    if is(.value = open_result, .variant = ..error) {
        result = ..error(.reason = ..path_open_failed)
        return
    }
    file ::= open_result..ok.value

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

    result = ..ok(.value = Void())
}

write_file(
    .self: &FileSystem,
    .path: &String,
    .text: String,
) -> (.result: Errable#(.t: Void, .reasons: (..path_open_failed, ..stream_write_failed, ..stream_flush_failed, ..stream_close_failed))) := {
    c_path ::= as_c_string(.self = path)
    result = write_file(.self = self, .path = c_path, .text = text)
}

write_file(
    .self: &FileSystem,
    .path: StringView,
    .text: String,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..path_open_failed, ..stream_write_failed, ..stream_flush_failed, ..stream_close_failed))) := {
    c_path ::= as_c_string(.self = path, .allocator = allocator)
    result = write_file(.self = self, .path = c_path.text, .text = text)
}

write_file(
    .self: &FileSystem,
    .path: &Path,
    .text: String,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..path_open_failed, ..stream_write_failed, ..stream_flush_failed, ..stream_close_failed))) := {
    result = write_file(.self = self, .path = &path&.text, .text = text)
}
