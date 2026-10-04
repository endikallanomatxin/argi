#if target_os("windows") {
    _windows_monotonic(.seconds: $&UInt64, .nanoseconds: $&UInt32) -> (.status: Int32): CFunction(
        .symbol = "_argi_clock_monotonic"
    )
    _windows_wall(.seconds: $&Int64, .nanoseconds: $&UInt32) -> (.status: Int32): CFunction(
        .symbol = "_argi_clock_wall"
    )
    _windows_sleep(.seconds: UInt64, .nanoseconds: UInt32) -> (.status: Int32): CFunction(
        .symbol = "_argi_clock_sleep"
    )
    _platform_monotonic(.ffi: $&ForeignFunctionInterface = reach ffi) -> (
        .status      : Int32,
        .seconds     : UInt64 = 0,
        .nanoseconds : UInt32 = 0
    ) := {
        assume ffi
        status = _windows_monotonic(.seconds = $&seconds, .nanoseconds = $&nanoseconds).status
    }
    _platform_wall(.ffi: $&ForeignFunctionInterface = reach ffi) -> (
        .status      : Int32,
        .seconds     : Int64  = 0,
        .nanoseconds : UInt32 = 0
    ) := {
        assume ffi
        status = _windows_wall(.seconds = $&seconds, .nanoseconds = $&nanoseconds).status
    }
    _platform_sleep(
        .seconds     : UInt64,
        .nanoseconds : UInt32,
        .ffi         : $&ForeignFunctionInterface = reach ffi
    ) -> (.status: Int32) := {
        assume ffi
        status = _windows_sleep(.seconds = seconds, .nanoseconds = nanoseconds).status
    }
}
