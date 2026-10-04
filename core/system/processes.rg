-- The native adapter owns temporary argument copies and opaque child records.
-- Addresses are private handles, never safe references or acquisition receipts.
_process_builder() -> (.address: UIntNative): CFunction(.symbol = "_argi_process_builder")

_process_argument(.builder: UIntNative, .bytes: &UInt8, .length: UIntNative) -> (.status: Int32): CFunction(
    .symbol = "_argi_process_argument"
)

_process_builder_free(.builder: UIntNative) -> (): CFunction(
    .symbol = "_argi_process_builder_free"
)

_process_spawn(
        .builder : UIntNative,
        .input   : Int32,
        .output  : Int32,
        .error   : Int32,
        .handle  : $&UIntNative,
        .stdin   : $&UIntNative,
        .stdout  : $&UIntNative,
        .stderr  : $&UIntNative,
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_process_spawn")

_process_wait(.handle: UIntNative, .code: $&UInt32, .signal: $&UInt32) -> (.status: Int32): CFunction(
    .symbol = "_argi_process_wait"
)

_process_terminate(.handle: UIntNative) -> (.status: Int32): CFunction(
    .symbol = "_argi_process_terminate"
)

_process_free(.handle: UIntNative) -> (): CFunction(.symbol = "_argi_process_free")

_process_stream_close(.handle: UIntNative) -> (.status: Int32): CFunction(
    .symbol = "_argi_process_stream_close"
)

_process_stream_read(.handle: UIntNative, .byte: $&UInt8) -> (.status: Int32): CFunction(
    .symbol = "_argi_process_stream_read"
)

_process_stream_write(.handle: UIntNative, .byte: UInt8) -> (.status: Int32): CFunction(
    .symbol = "_argi_process_stream_write"
)

ProcessManager: Type = (._ffi: $&ForeignFunctionInterface)

once ProcessManager init(.ffi: $&ForeignFunctionInterface = reach ffi) -> (.result: ProcessManager) := {
    result = (._ffi = ffi)
}

ProcessStreamMode: Type = (..inherit, ..pipe, ..discard)

ProcessStreamMode implements ImplicitlyCopyable

ProcessExitStatus: Type = (..exited(.code: UInt32), ..signaled(.signal: UInt32))

ProcessExitStatus implements ImplicitlyCopyable

..invalid_process_argument
..process_spawn_failed
..process_wait_failed
..process_terminate_failed

-- Unbuffered endpoints are owned by their process. An inherited/discarded
-- stream has no parent endpoint; direction is checked before crossing FFI.
ProcessStream: Type = (
    ._ffi      : $&ForeignFunctionInterface
    ._handle   : UIntNative
    ._writable : Bool
)

ProcessStream implements Reader
ProcessStream implements Writer

Process: Type = (
    ._ffi    : $&ForeignFunctionInterface
    ._handle : UIntNative
    .stdin   : ProcessStream
    .stdout  : ProcessStream
    .stderr  : ProcessStream
)

_process_mode(.value: ProcessStreamMode) -> (.mode: Int32) := {
    if is(.value = value, .variant = ..pipe) {
        mode = 1
        return
    }
    if is(.value = value, .variant = ..discard) {
        mode = 2
        return
    }
    mode = 0
}

_process_no_arguments() -> (.value: ArrayViewRO#(.t: StringView)) := {
    value = array_view_ro#(.t: StringView)()
}

_process_inherit() -> (.value: ProcessStreamMode) := { value = ..inherit }

spawn(
        .executable : StringView,
        .arguments  : ArrayViewRO#(.t: StringView) = _process_no_arguments(),
        .stdin      : ProcessStreamMode            = _process_inherit(),
        .stdout     : ProcessStreamMode            = _process_inherit(),
        .stderr     : ProcessStreamMode            = _process_inherit(),
        .self       : &ProcessManager              = reach proc_man,
    ) -> (
        .result : Errable#(
            .t       : Process,
            .reasons : (..invalid_process_argument, ..out_of_memory, ..process_spawn_failed)
        )
    ) := {
    assume ffi := self&._ffi
    builder ::= _process_builder().address
    if builder == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    status :: Int32 = _process_argument(
        .builder = builder
        .bytes   = executable.data
        .length  = executable.length
    ).status
    i :: UIntNative = 0
    while status == 0 and i < length(.self = &arguments).count {
        argument ::= unwrap_or_abort(.value = get_ro_ref(.self = &arguments, .index = i)).result
        status = _process_argument(
            .builder = builder
            .bytes   = argument&.data
            .length  = argument&.length
        ).status
        i = i + 1
    }
    handle :: UIntNative = 0
    input :: UIntNative = 0
    output :: UIntNative = 0
    error :: UIntNative = 0
    if status == 0 {
        status = _process_spawn(
            .builder = builder
            .input   = _process_mode(.value = stdin).mode
            .output  = _process_mode(.value = stdout).mode
            .error   = _process_mode(.value = stderr).mode
            .handle  = $&handle
            .stdin   = $&input
            .stdout  = $&output
            .stderr  = $&error
        ).status
    }
    _process_builder_free(.builder = builder)
    if status == -2 {
        result = ..error(.reason = ..invalid_process_argument)
        return
    }
    if status == -3 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    if status != 0 {
        result = ..error(.reason = ..process_spawn_failed)
        return
    }
    result = ..ok(
        ._ffi    = self&._ffi
        ._handle = handle
        .stdin   = (._ffi = self&._ffi, ._handle = input, ._writable = true)
        .stdout  = (._ffi = self&._ffi, ._handle = output, ._writable = false)
        .stderr  = (._ffi = self&._ffi, ._handle = error, ._writable = false)
    )
}

wait(
        .self : $&Process
    ) -> (
        .result : Errable#(
            .t       : ProcessExitStatus,
            .reasons : (..process_wait_failed)
        )
    ) := {
    assume ffi := self&._ffi
    if self&._handle == 0 {
        result = ..error(.reason = ..process_wait_failed)
        return
    }
    code :: UInt32 = 0
    signal :: UInt32 = 0
    if _process_wait(.handle = self&._handle, .code = $&code, .signal = $&signal).status != 0 {
        result = ..error(.reason = ..process_wait_failed)
        return
    }
    if signal != 0 {
        result = ..ok ..signaled(.signal = signal)
        return
    }
    result = ..ok ..exited(.code = code)
}

terminate(
        .self : $&Process
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..process_terminate_failed))
    ) := {
    assume ffi := self&._ffi
    if self&._handle == 0 {
        result = ..error(.reason = ..process_terminate_failed)
        return
    }
    if _process_terminate(.handle = self&._handle).status != 0 {
        result = ..error(.reason = ..process_terminate_failed)
        return
    }
    result = ..ok Void()
}

is_open(.self: &ProcessStream) -> (.ok: Bool) := { ok = self&._handle != 0 }

close(.self: $&ProcessStream) -> (.result: Errable#(.t: Void, .reasons: (..stream_close_failed))) := {
    assume ffi := self&._ffi
    handle ::= self&._handle
    self&._handle = 0
    if _process_stream_close(.handle = handle).status != 0 {
        result = ..error(.reason = ..stream_close_failed)
        return
    }
    result = ..ok Void()
}

read_byte(
        .self : $&ProcessStream
    ) -> (
        .result : Errable#(
            .t       : ReadByte,
            .reasons : (..stream_read_failed)
        )
    ) := {
    assume ffi := self&._ffi
    if self&._handle == 0 or self&._writable {
        result = ..error(.reason = ..stream_read_failed)
        return
    }
    byte :: UInt8 = 0
    status ::= _process_stream_read(.handle = self&._handle, .byte = $&byte).status
    if status < 0 {
        result = ..error(.reason = ..stream_read_failed)
        return
    }
    if status == 0 {
        result = ..ok ..end
        return
    }
    result = ..ok ..ok byte
}

write_byte(
        .self : $&ProcessStream,
        .byte : UInt8
    ) -> (
        .result : Errable#(
            .t       : Void,
            .reasons : (..stream_write_failed, ..stream_flush_failed)
        )
    ) := {
    assume ffi := self&._ffi
    if self&._handle == 0 or self&._writable == false {
        result = ..error(.reason = ..stream_write_failed)
        return
    }
    if _process_stream_write(.handle = self&._handle, .byte = byte).status != 0 {
        result = ..error(.reason = ..stream_write_failed)
        return
    }
    result = ..ok Void()
}

flush(
        .self : $&ProcessStream
    ) -> (
        .result : Errable#(
            .t       : Void,
            .reasons : (..stream_write_failed, ..stream_flush_failed)
        )
    ) := {
    if self&._handle == 0 or self&._writable == false {
        result = ..error(.reason = ..stream_flush_failed)
        return
    }
    result = ..ok Void()
}

ProcessStream deinit(.self: $&ProcessStream) -> () := {
    assume ffi := self&._ffi
    _process_stream_close(.handle = self&._handle)
    self&._handle = 0
}

Process deinit(.self: $&Process) -> () := {
    assume ffi := self&._ffi
    deinit(.self = $&self&.stdin)
    deinit(.self = $&self&.stdout)
    deinit(.self = $&self&.stderr)
    _process_free(.handle = self&._handle)
    self&._handle = 0
}
