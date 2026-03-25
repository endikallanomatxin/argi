__argi_runtime_argc() -> (.count: UIntNative) : ExternFunction
__argi_runtime_argv() -> (.argv: UIntNative) : ExternFunction

Arguments : Type = (
    .count : UIntNative
    .argv  : UIntNative
)

ArgumentsIterator : Type = (
    .args  : &Arguments
    .index : UIntNative
)

ArgumentsIterator implements Iterator#(.t: StringView)
Arguments implements Iterable#(.t: StringView)

init(.p: $&Arguments) -> () := {
    p& = (
        .count = __argi_runtime_argc().count,
        .argv = __argi_runtime_argv().argv,
    )
}

argument_count(.self: &Arguments) -> (.count: UIntNative) := {
    count = self&.count
}

length(.self: &Arguments) -> (.count: UIntNative) := {
    count = self&.count
}

has_argument(
    .self: &Arguments,
    .index: UIntNative,
) -> (.ok: Bool) := {
    ok = index < self&.count
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

operator get[](
    .self: &Arguments,
    .index: UIntNative,
) -> (.view: StringView) := {
    view = argument_view_at(.self = self, .index = index)
}

to_iterator(
    .value: &Arguments,
) -> (.iterator: ArgumentsIterator) := {
    iterator = (
        .args = value,
        .index = 0,
    )
}

has_next(
    .self: &ArgumentsIterator,
) -> (.ok: Bool) := {
    ok = self&.index < self&.args&.count
}

next(
    .self: $&ArgumentsIterator,
) -> (.value: StringView) := {
    current_index :: UIntNative = self&.index
    value = self&.args[current_index]
    self& = (
        .args = self&.args,
        .index = current_index + 1,
    )
}
