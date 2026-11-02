unsupported_host_call() -> (.value: Int32): CFunction(
    .symbol = "argi_unregistered_compile_time_operation"
)

answer ::= #run (.system: System) -> (.value: Int32) {
    assume ffi ::= system.ffi
    value = unsupported_host_call()
}

main := () -> (.status_code: Int32) { status_code = answer }
