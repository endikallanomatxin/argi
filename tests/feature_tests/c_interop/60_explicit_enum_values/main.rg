state := import("./dep")

argi_enum_next(.status: state.Status) -> (.result: state.Status)
    : CFunction(.export = true) := {
    match status {
        ..negative { result = ..following_negative }
        ..following_negative { result = ..ready }
        ..ready { result = ..following_ready }
        ..following_ready { result = ..hexadecimal }
        ..hexadecimal { result = ..binary }
        ..binary { result = ..octal }
        ..octal { result = ..minimum }
        ..minimum { result = ..maximum }
        ..maximum { result = ..negative }
    }
}

_probe() -> (.result: CInt) : CFunction(.symbol = "argi_enum_probe")
_echo(.value: state.Status) -> (.result: state.Status) : CFunction(.symbol = "argi_enum_echo")

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    status_code = _probe()
    value := _echo(.value = ..following_negative)
    if value != ..following_negative {
        status_code = 10
    }
}
