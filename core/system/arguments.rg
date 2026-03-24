__argi_runtime_argc() -> (.count: UIntNative) : ExternFunction
__argi_runtime_argv() -> (.argv: UIntNative) : ExternFunction

Arguments : Type = (
    .count : UIntNative
    .argv  : UIntNative
)

init(.p: $&Arguments) -> () := {
    p& = (
        .count = __argi_runtime_argc().count,
        .argv = __argi_runtime_argv().argv,
    )
}

argument_count(.self: &Arguments) -> (.count: UIntNative) := {
    count = self&.count
}
