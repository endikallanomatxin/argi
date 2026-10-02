FileOpenMode : Type = (
    ..read
    ..write
    ..append
)

FileOpenMode implements ImplicitlyCopyable
..file_open_failed

File : Type = (
    ._ffi: $&ForeignFunctionInterface
    .stream_address : UIntNative = 0
    .should_close   : Bool = 0 == 1
)

once init(.p: $&File, .ffi: $&ForeignFunctionInterface = reach ffi) -> () := {
    p& = (._ffi = ffi, .stream_address = 0, .should_close = false)
}

init(
    .p: $&File,
    .ffi: $&ForeignFunctionInterface = reach ffi,
    .stream_address: UIntNative,
    .should_close: Bool,
) -> () := {
    p& = (
        ._ffi = ffi,
        .stream_address = stream_address,
        .should_close = should_close,
    )
}

is_open(.self: &File) -> (.ok: Bool) := {
    ok = self&.stream_address != 0
}

file_open_mode_c_string(
    .mode: FileOpenMode,
) -> (.text: &Char) := {
    if is(.value = mode, .variant = ..read) {
        text = "rb"
        return
    }

    if is(.value = mode, .variant = ..write) {
        text = "wb"
        return
    }

    text = "ab"
}

file_stream_pointer(.self: &File) -> (.stream: &Any) := {
    raw ::= raw_pointer#(.t: Any)(.address = self&.stream_address)
    mutable_stream ::= trusted_establish_inherited_reference#(.t: Any)(
        .raw = raw,
        .root = erase_reference#(.t: File)(.base = self).reference,
    )
    stream = read_reference#(.t: Any)(.base = mutable_stream)
}

open(
    .p: $&File,
    .ffi: $&ForeignFunctionInterface = reach ffi,
    .path: &Char,
    .mode: FileOpenMode,
) -> (.result: Errable#(.t: Bool, .reasons: (..file_open_failed))) := {
    mode_text ::= file_open_mode_c_string(.mode = mode)
    opened : &Any = fopen(.path = path, .mode = mode_text)
    p& = (
        ._ffi = ffi,
        .stream_address = UIntNative(.value = opened),
        .should_close = 1 == 1,
    )
    if p&.stream_address == 0 {
        result = ..error(.reason = ..file_open_failed)
        return
    }
    result = ..ok 1 == 1
}

open_read(
    .p: $&File,
    .ffi: $&ForeignFunctionInterface = reach ffi,
    .path: &Char,
) -> (.result: Errable#(.t: Bool, .reasons: (..file_open_failed))) := {
    result = open(.p = p, .path = path, .mode = ..read)
}

open_write(
    .p: $&File,
    .ffi: $&ForeignFunctionInterface = reach ffi,
    .path: &Char,
) -> (.result: Errable#(.t: Bool, .reasons: (..file_open_failed))) := {
    result = open(.p = p, .path = path, .mode = ..write)
}

open_append(
    .p: $&File,
    .ffi: $&ForeignFunctionInterface = reach ffi,
    .path: &Char,
) -> (.result: Errable#(.t: Bool, .reasons: (..file_open_failed))) := {
    result = open(.p = p, .path = path, .mode = ..append)
}

init_stdin(.p: $&File, .ffi: $&ForeignFunctionInterface = reach ffi) -> () := {
    mode_text ::= file_open_mode_c_string(.mode = ..read)
    stream : &Any = fdopen(.fd = 0, .mode = mode_text)
    p& = (
        ._ffi = ffi,
        .stream_address = UIntNative(.value = stream),
        .should_close = 0 == 1,
    )
}

init_stdout(.p: $&File, .ffi: $&ForeignFunctionInterface = reach ffi) -> () := {
    mode_text ::= file_open_mode_c_string(.mode = ..write)
    stream : &Any = fdopen(.fd = 1, .mode = mode_text)
    p& = (
        ._ffi = ffi,
        .stream_address = UIntNative(.value = stream),
        .should_close = 0 == 1,
    )
}

init_stderr(.p: $&File, .ffi: $&ForeignFunctionInterface = reach ffi) -> () := {
    mode_text ::= file_open_mode_c_string(.mode = ..write)
    stream : &Any = fdopen(.fd = 2, .mode = mode_text)
    p& = (
        ._ffi = ffi,
        .stream_address = UIntNative(.value = stream),
        .should_close = 0 == 1,
    )
}

close(.self: $&File) -> (.result: Errable#(.t: Void, .reasons: (..stream_close_failed))) := {
    assume ffi := self&._ffi
    if self&.stream_address == 0 {
        result = ..ok Void()
        return
    }

    close_failed :: Bool = false
    if self&.should_close {
        stream ::= file_stream_pointer(.self = self).stream
        close_status ::= fclose(.stream = stream).status
        close_failed = close_status != 0
    }

    self& = (
        ._ffi = self&._ffi,
        .stream_address = 0,
        .should_close = 0 == 1,
    )

    if close_failed {
        result = ..error(.reason = ..stream_close_failed)
        return
    }

    result = ..ok Void()
}

flush(.self: $&File) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume ffi := self&._ffi
    if self&.stream_address == 0 {
        result = ..error(.reason = ..stream_flush_failed)
        return
    }

    if fflush(.stream = file_stream_pointer(.self = self).stream).status != 0 {
        result = ..error(.reason = ..stream_flush_failed)
        return
    }

    result = ..ok Void()
}

read_byte(.self: $&File) -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed))) := {
    assume ffi := self&._ffi
    if self&.stream_address == 0 {
        result = ..error(.reason = ..stream_read_failed)
        return
    }

    byte :: UInt8 = 0
    byte_view ::= array_view#(.t: UInt8)(.data = $&byte)
    read_count ::= fread_into(
        .buffer = byte_view,
        .stream = file_stream_pointer(.self = self).stream,
    ).count

    if read_count == 0 {
        stream ::= file_stream_pointer(.self = self).stream
        if ferror(.stream = stream).status != 0 {
            result = ..error(.reason = ..stream_read_failed)
            return
        }

        if feof(.stream = stream).status != 0 {
            result = ..ok ..end
            return
        }

        result = ..error(.reason = ..stream_read_failed)
        return
    }

    result = ..ok ..ok byte
}

write_byte(.self: $&File, .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume ffi := self&._ffi
    if self&.stream_address == 0 {
        result = ..error(.reason = ..stream_write_failed)
        return
    }

    single_byte :: UInt8 = byte
    byte_view ::= array_view#(.t: UInt8)(.data = $&single_byte)
    wrote ::= fwrite_from(
        .buffer = byte_view,
        .stream = file_stream_pointer(.self = self).stream,
    ).count

    if wrote != 1 {
        result = ..error(.reason = ..stream_write_failed)
        return
    }

    result = ..ok Void()
}

read(
    .self: $&File,
    .buffer: ArrayView#(.t: UInt8),
) -> (.result: Errable#(.t: UIntNative, .reasons: (..stream_read_failed))) := {
    assume ffi := self&._ffi
    if self&.stream_address == 0 {
        result = ..error(.reason = ..stream_read_failed)
        return
    }

    stream ::= file_stream_pointer(.self = self).stream
    read_count ::= fread_into(.buffer = buffer, .stream = stream).count

    if read_count < length#(.t: UInt8)(.self = &buffer).count {
        if ferror(.stream = stream).status != 0 {
            result = ..error(.reason = ..stream_read_failed)
            return
        }
    }

    result = ..ok read_count
}

write(
    .self: $&File,
    .buffer: ArrayView#(.t: UInt8),
) -> (.result: Errable#(.t: UIntNative, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume ffi := self&._ffi
    if self&.stream_address == 0 {
        result = ..error(.reason = ..stream_write_failed)
        return
    }

    stream ::= file_stream_pointer(.self = self).stream
    wrote ::= fwrite_from(.buffer = buffer, .stream = stream).count

    if wrote < length#(.t: UInt8)(.self = &buffer).count {
        if ferror(.stream = stream).status != 0 {
            result = ..error(.reason = ..stream_write_failed)
            return
        }
    }

    result = ..ok wrote
}

File implements Reader
File implements Writer
