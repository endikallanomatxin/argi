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

argument_pointer_address(
    .self: &Arguments,
    .index: UIntNative,
) -> (.address: UIntNative) := {
    stride :: UIntNative = size_of(.type = UIntNative)
    address = self&.argv + index * stride
}

argument_at(
    .self: &Arguments,
    .index: UIntNative,
) -> (.text: CString) := {
    addr ::= argument_pointer_address(.self = self, .index = index).address
    ptr : &UIntNative = cast#(.to: &UIntNative)(.value = addr)
    text = (
        .data = ptr&
    )
}

argument_view_at(
    .self: &Arguments,
    .index: UIntNative,
) -> (.view: StringView) := {
    text ::= argument_at(.self = self, .index = index)
    c_ptr ::= pointer(.self = &text)
    view = (
        .data = text.data,
        .length = strlen(.string = c_ptr).length,
    )
}
