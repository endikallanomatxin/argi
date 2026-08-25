argi_runtime_argc() -> (.count: UIntNative) : ExternFunction
argi_runtime_argv() -> (.address: UIntNative) : ExternFunction

Arguments : Type = (
    .count   : UIntNative
    .address : UIntNative
)

ArgumentsIterator : Type = (
    .args  : &Arguments
    .index : UIntNative
)

ArgumentsIterator implements Iterator#(.t: StringView)
Arguments implements Iterable#(.t: StringView)

once init(.p: $&Arguments) -> () := {
    p& = (
        .count = argi_runtime_argc().count,
        .address = argi_runtime_argv().address,
    )
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
    address = self&.address + index * stride
}

argument_at(
    .self: &Arguments,
    .index: UIntNative,
) -> (.text: &Char) #trusted_temporal := {
    addr ::= argument_pointer_address(.self = self, .index = index).address
    ptr : &UIntNative = cast#(.to: &UIntNative)(.value = addr)
    text = cast#(.to: &Char)(.value = ptr&)
}

argument_view_at(
    .self: &Arguments,
    .index: UIntNative,
) -> (.view: StringView) := {
    text ::= argument_at(.self = self, .index = index)
    view = (
        .data = cast#(.to: UIntNative)(.value = text),
        .length = strlen(.string = text).length,
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
