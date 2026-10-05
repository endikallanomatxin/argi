#if target_os("linux") or target_os("macos") {
    -- Supported POSIX targets use a 64-bit time_t and long in struct timespec.
    _PosixTimespec: CStruct = (.seconds: CLong, .nanoseconds: CLong)
    _clock_gettime(.id: CInt, .time: $&_PosixTimespec) -> (.status: CInt): CFunction(
        .symbol = "clock_gettime"
    )
    _clock_nanosleep(.request: &_PosixTimespec, .remaining: $&_PosixTimespec) -> (.status: CInt): CFunction(
        .symbol = "nanosleep"
    )
    #if target_os("linux") {
        _clock_errno() -> (.pointer: RawPointer#(.t: CInt)): CFunction(
            .symbol = "__errno_location"
        )
    }#else {
        _clock_errno() -> (.pointer: RawPointer#(.t: CInt)): CFunction(.symbol = "__error")
    }

    _platform_monotonic(.ffi: $&ForeignFunctionInterface = reach ffi) -> (
        .status      : Int32  = -1,
        .seconds     : UInt64 = 0,
        .nanoseconds : UInt32 = 0
    ) := {
        assume ffi
        time :: _PosixTimespec = (.seconds = 0, .nanoseconds = 0)
        id :: CInt = 1
        #if target_os("macos") { id = 6 }
        if _clock_gettime(.id = id, .time = $&time).status != 0 { return }
        if time.seconds < 0 or time.nanoseconds < 0 or time.nanoseconds >= 1000000000 { return }
        seconds = unwrap_or_abort(.value = UInt64(.value = time.seconds)).result
        nanoseconds = unwrap_or_abort(.value = UInt32(.value = time.nanoseconds)).result
        status = 0
    }

    _platform_wall(.ffi: $&ForeignFunctionInterface = reach ffi) -> (
        .status      : Int32  = -1,
        .seconds     : Int64  = 0,
        .nanoseconds : UInt32 = 0
    ) := {
        assume ffi
        time :: _PosixTimespec = (.seconds = 0, .nanoseconds = 0)
        if _clock_gettime(.id = 0, .time = $&time).status != 0 { return }
        if time.nanoseconds < 0 or time.nanoseconds >= 1000000000 { return }
        seconds = time.seconds
        nanoseconds = unwrap_or_abort(.value = UInt32(.value = time.nanoseconds)).result
        status = 0
    }

    _platform_sleep(
        .seconds     : UInt64,
        .nanoseconds : UInt32,
        .ffi         : $&ForeignFunctionInterface = reach ffi
    ) -> (.status: Int32 = -1) := {
        assume ffi
        unspent ::= seconds
        fraction ::= nanoseconds
        -- Native kernels may use signed nanosecond deadlines even when time_t
        -- is wider. Finite day-sized intervals avoid truncating a long delay.
        while unspent != 0 or fraction != 0 {
            chunk ::= unspent
            chunk_fraction ::= fraction
            if chunk >= 86400 { chunk = 86400 chunk_fraction = 0 }
            request :: _PosixTimespec = (
                .seconds     = unwrap_or_abort(.value = Int64(.value = chunk)).result,
                .nanoseconds = Int64(.value = chunk_fraction),
            )
            remaining :: _PosixTimespec = (.seconds = 0, .nanoseconds = 0)
            while true {
                if _clock_nanosleep(.request = &request, .remaining = $&remaining).status == 0 {
                    break
                }
                -- errno is live thread-local C storage throughout this synchronous
                -- call. Its FFI root bounds the borrow without acquiring storage.
                raw ::= _clock_errno().pointer
                root ::= erase_mutable_reference(.base = ffi).reference
                error ::= trusted_establish_inherited_reference#(.t: CInt)(
                    .raw  = raw,
                    .root = root
                ).reference&
                if error != 4 { return }
                if remaining.seconds < 0 or remaining.nanoseconds < 0 or remaining.nanoseconds >= 1000000000 {
                    return
                }
                request = remaining
            }
            unspent = unspent - chunk
            fraction = fraction - chunk_fraction
        }
        status = 0
    }
}
