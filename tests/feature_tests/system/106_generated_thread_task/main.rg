Callback(.value: CInt) -> (.result: CInt): CFunctionPointer

compute := (.value: CInt) -> (.result: CInt) { result = value + value }
worker := #(.F: Function) (.value: CInt) -> (.result: CInt): CFunction {
    result = F(.value = value)
}

run_task(.callback: Callback, .value: CInt) -> (.result: CInt)
: CFunction(.symbol = "argi_generated_thread_task")

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume ffi := system.ffi
    callback := Callback(.function = worker#(compute))
    if run_task(.callback = callback, .value = 21) != 42 { status_code = 1 }
}
