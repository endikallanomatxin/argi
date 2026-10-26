_FileInitArgs: Type = (.ffi: $&ForeignFunctionInterface = reach ffi)

FileOpenMode: Type = (
    ..read
    ..write
    ..append
)

implement ImplicitlyCopyable#(FileOpenMode) ()

..file_open_failed

File: Type = (
    ._ffi           : $&ForeignFunctionInterface
    .stream_address : UIntNative                 = 0
    .should_close   : Bool                       = 0 == 1
)

once _acquire_file := (.args: _FileInitArgs) -> (.result: File) {
    ffi ::= args.ffi

    result = (._ffi = ffi, .stream_address = 0, .should_close = false)
}

implement Init#(File, _FileInitArgs) (
    .Result : Type = File
    .init   = _acquire_file
)

implement Init#(
    File,
    (
        .ffi            : $&ForeignFunctionInterface = reach ffi,
        .stream_address : UIntNative,
        .should_close   : Bool
    )
) (
    .Result : Type = File
    .init   = (
        .args : (
            .ffi            : $&ForeignFunctionInterface = reach ffi,
            .stream_address : UIntNative,
            .should_close   : Bool
        )
    ) -> (.result: Result) {
        ffi ::= args.ffi
        stream_address ::= args.stream_address
        should_close ::= args.should_close

        result = (._ffi = ffi, .stream_address = stream_address, .should_close = should_close)
    }
)

_is_open_File(.self: &File) -> (.ok: Bool) := {
    ok = self&.stream_address != 0
}

file_open_mode_c_string(.mode: FileOpenMode) -> (.text: &CChar) := {
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
        .raw = raw, .root = erase_reference#(.t: File)(.base = self).reference
    )
    stream = read_reference#(.t: Any)(.base = mutable_stream)
}

open := (
    .p: $&File, .ffi: $&ForeignFunctionInterface = reach ffi, .path: &CChar, .mode: FileOpenMode
) -> (.result: Errable#(Bool, (..file_open_failed))) {
    mode_text ::= file_open_mode_c_string(.mode = mode)
    opened: &Any = fopen(.path = path, .mode = mode_text)
    p&= (
        ._ffi           = ffi
        .stream_address = opened | convert#(.to: UIntNative)(_)
        .should_close   = 1 == 1
    )

    if p&.stream_address == 0 {
        result = ..error(.reason = ..file_open_failed)
        return
    }

    result = ..ok 1 == 1
}

_standard_stream(.descriptor: Int32) -> (.stream: UIntNative): CFunction(
    .symbol = "_argi_standard_stream"
)

_file_write_byte(.stream: UIntNative, .byte: UInt8) -> (.status: Int32): CFunction(
    .symbol = "_argi_file_write_byte"
)

_file_flush(.stream: UIntNative) -> (.status: Int32): CFunction(
    .symbol = "_argi_file_flush"
)

_file_close(.stream: UIntNative) -> (.status: Int32): CFunction(
    .symbol = "_argi_file_close"
)

init_stdin(.p: $&File, .ffi: $&ForeignFunctionInterface = reach ffi) -> () := {
    p&= (
        ._ffi           = ffi
        .stream_address = _standard_stream(.descriptor = 0)
        .should_close   = false
    )
}

init_stdout(.p: $&File, .ffi: $&ForeignFunctionInterface = reach ffi) -> () := {
    p&= (
        ._ffi           = ffi
        .stream_address = _standard_stream(.descriptor = 1)
        .should_close   = false
    )
}

init_stderr(.p: $&File, .ffi: $&ForeignFunctionInterface = reach ffi) -> () := {
    p&= (
        ._ffi           = ffi
        .stream_address = _standard_stream(.descriptor = 2)
        .should_close   = false
    )
}

_close_File(.self: $&File) -> (.result: Errable#(Void, (..stream_close_failed))) := {
    assume ffi := self&._ffi

    if self&.stream_address == 0 {
        result = ..ok Void()
        return
    }

    close_failed ::= false

    if self&.should_close {
        close_status ::= _file_close(.stream = self&.stream_address).status
        close_failed = close_status != 0
    }

    self&= (
        ._ffi           = self&._ffi
        .stream_address = 0
        .should_close   = 0 == 1
    )

    if close_failed {
        result = ..error(.reason = ..stream_close_failed)
        return
    }

    result = ..ok Void()
}

implement Reader#(File) (
    .read_byte = (.self: $&File) -> (.result: Errable#(ReadByte, (..stream_read_failed))) {
        assume ffi := self&._ffi

        if self&.stream_address == 0 {
            result = ..error(.reason = ..stream_read_failed)
            return
        }

        byte :: UInt8 = 0
        byte_view ::= single_mutable_array_view#(.t: UInt8)(.data = $&byte)
        read_count ::= fread_into(
            .buffer = byte_view, .stream = file_stream_pointer(self).stream
        ).count

        if read_count == 0 {
            stream ::= file_stream_pointer(self).stream
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
)

_read_file(.self: $&File, .buffer: MutableArrayView#(.t: UInt8)) -> (
    .result : Errable#(UIntNative, (..stream_read_failed))
) := {
    assume ffi := self&._ffi

    if self&.stream_address == 0 {
        result = ..error(.reason = ..stream_read_failed)
        return
    }

    stream ::= file_stream_pointer(self).stream
    read_count ::= fread_into(.buffer = buffer, .stream = stream).count

    if read_count < length(&buffer).count {
        if ferror(.stream = stream).status != 0 {
            result = ..error(.reason = ..stream_read_failed)
            return
        }
    }

    result = ..ok read_count
}

_file_write(.self: $&File, .value: MutableArrayView#(.t: UInt8)) -> (
    .result : Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
) := {
    assume ffi := self&._ffi

    if self&.stream_address == 0 {
        result = ..error(.reason = ..stream_write_failed)
        return
    }

    stream ::= file_stream_pointer(self).stream
    wrote ::= fwrite_from(.buffer = value, .stream = stream).count

    if wrote < length(&value).count {
        if ferror(.stream = stream).status != 0 {
            result = ..error(.reason = ..stream_write_failed)
            return
        }
    }

    result = ..ok wrote
}

implement WriteValue#(File, MutableArrayView#(.t: UInt8)) (
    .Result      : Type = Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
    .write_value = _file_write
)

implement BlockWriter#(File) (
    .write_block = (.self: $&File, .buffer: ArrayView#(.t: UInt8)) -> (
        .result : Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
    ) {
        assume ffi := self&._ffi

        if self&.stream_address == 0 {
            result = ..error(.reason = ..stream_write_failed)
            return
        }

        stream ::= file_stream_pointer(self).stream
        count ::= fwrite_from(.buffer = buffer, .stream = stream).count

        if count < length(&buffer).count {
            if ferror(.stream = stream).status != 0 {
                result = ..error(.reason = ..stream_write_failed)
                return
            }
        }

        result = ..ok count
    }
)

implement Writer#(File) (
    .flush = (.self: $&File) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        assume ffi := self&._ffi

        if self&.stream_address == 0 {
            result = ..error(.reason = ..stream_flush_failed)
            return
        }

        if _file_flush(.stream = self&.stream_address).status != 0 {
            result = ..error(.reason = ..stream_flush_failed)
            return
        }

        result = ..ok Void()
    }

    .write_byte = (.self: $&File, .byte: UInt8) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        assume ffi := self&._ffi

        if self&.stream_address == 0 {
            result = ..error(.reason = ..stream_write_failed)
            return
        }

        if _file_write_byte(.stream = self&.stream_address, .byte = byte).status != 0 {
            result = ..error(.reason = ..stream_write_failed)
            return
        }

        result = ..ok Void()
    }
)

implement Closeable#(File) (
    .Result         : Type = Errable#(Void, (..stream_close_failed))
    .close_resource = _close_File
)

implement OpenState#(File) (.check_open = _is_open_File)

implement BufferReading#(File) (
    .Result : Type = Errable#(UIntNative, (..stream_read_failed))
    .read   = _read_file
)
