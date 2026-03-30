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

    initial_capacity :: UIntNative = 16
    zero :: UIntNative = 0
    capacity :: UIntNative = initial_capacity
    allocation_size :: UIntNative = capacity + 1
    buffer :: $&UInt8 = allocate(.self = allocator, .size = allocation_size)
    if cast#(.to: UIntNative)(.value = buffer) == 0 {
        _ ::= close(.self = $&file)
        result = ..error(.reason = ..out_of_memory)
        return
    }
    length :: UIntNative = zero
    initial_terminator_ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = buffer))
    initial_terminator_ptr& = 0

    while 1 == 1 {
        next ::= read_byte(.self = $&file)
        if is(.value = next, .variant = ..error) {
            deallocate(.self = allocator, .data = buffer, .size = allocation_size)
            _ ::= close(.self = $&file)
            result = ..error(.reason = ..stream_read_failed)
            return
        }

        next_value ::= next..ok.value
        if is(.value = next_value, .variant = ..end) {
            break
        }

        if length == capacity {
            new_capacity :: UIntNative = capacity * 2
            new_allocation_size :: UIntNative = new_capacity + 1
            new_buffer : $&UInt8 = allocate(.self = allocator, .size = new_allocation_size)
            if cast#(.to: UIntNative)(.value = new_buffer) == 0 {
                deallocate(.self = allocator, .data = buffer, .size = allocation_size)
                _ ::= close(.self = $&file)
                result = ..error(.reason = ..out_of_memory)
                return
            }
            memcpy(
                .dst = cast#(.to: $&Any)(.value = cast#(.to: UIntNative)(.value = new_buffer)),
                .src = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = buffer)),
                .n = length + 1,
            )
            deallocate(.self = allocator, .data = buffer, .size = allocation_size)
            buffer = new_buffer
            capacity = new_capacity
            allocation_size = new_allocation_size
        }

        payload ::= next_value..ok
        byte_ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = buffer) + length)
        byte_ptr& = payload.byte
        length = length + 1
        terminator_ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = buffer) + length)
        terminator_ptr& = 0
    }

    close_result ::= close(.self = $&file)
    if is(.value = close_result, .variant = ..error) {
        deallocate(.self = allocator, .data = buffer, .size = allocation_size)
        result = ..error(.reason = ..stream_close_failed)
        return
    }
    text :: String = (
        .allocation = (
            .data = buffer,
            .size = allocation_size,
        ),
        .length = length,
    )
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

write_file(
    .self: &FileSystem,
    .path: CString,
    .text: String,
) -> (.result: Errable#(.t: Bool, .reasons: (..path_open_failed, ..stream_write_failed, ..stream_flush_failed, ..stream_close_failed))) := {
    open_result ::= open_write(.self = self, .path = path)
    if is(.value = open_result, .variant = ..error) {
        result = ..error(.reason = ..path_open_failed)
        return
    }
    file ::= open_result..ok.value

    wrote ::= write(.self = $&file, .text = text)
    if is(.value = wrote, .variant = ..error) {
        _ ::= close(.self = $&file)
        wrote_reason ::= wrote..error.reason
        if is(.value = wrote_reason, .variant = ..stream_write_failed) {
            result = ..error(.reason = ..stream_write_failed)
        } else {
            result = ..error(.reason = ..stream_flush_failed)
        }
        return
    }

    flushed ::= flush(.self = $&file)
    if is(.value = flushed, .variant = ..error) {
        _ ::= close(.self = $&file)
        flushed_reason ::= flushed..error.reason
        if is(.value = flushed_reason, .variant = ..stream_write_failed) {
            result = ..error(.reason = ..stream_write_failed)
        } else {
            result = ..error(.reason = ..stream_flush_failed)
        }
        return
    }

    closed ::= close(.self = $&file)
    if is(.value = closed, .variant = ..error) {
        result = ..error(.reason = ..stream_close_failed)
        return
    }

    result = ..ok(.value = 1 == 1)
}

write_file(
    .self: &FileSystem,
    .path: &String,
    .text: String,
) -> (.result: Errable#(.t: Bool, .reasons: (..path_open_failed, ..stream_write_failed, ..stream_flush_failed, ..stream_close_failed))) := {
    c_path ::= as_c_string(.self = path)
    result = write_file(.self = self, .path = c_path, .text = text)
}

write_file(
    .self: &FileSystem,
    .path: StringView,
    .text: String,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Bool, .reasons: (..path_open_failed, ..stream_write_failed, ..stream_flush_failed, ..stream_close_failed))) := {
    c_path ::= as_c_string(.self = path, .allocator = allocator)
    result = write_file(.self = self, .path = c_path.text, .text = text)
}
