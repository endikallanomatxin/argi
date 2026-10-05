argi_runtime_argc() -> (.count: UIntNative): ExternFunction

argi_runtime_argv() -> (.address: UIntNative): ExternFunction

Arguments: Type = (
    ._ffi    : $&ForeignFunctionInterface
    .count   : UIntNative
    .address : UIntNative
)

ArgumentsIterator: Type = (
    .args  : &Arguments
    .index : UIntNative
)

ArgumentsIterator implements Iterator#(.t: StringView)
Arguments implements Iterable#(.t: StringView)

once Arguments init(.ffi: $&ForeignFunctionInterface = reach ffi) -> (.result: Arguments) := {
    result = (
        ._ffi    = ffi
        .count   = argi_runtime_argc().count
        .address = argi_runtime_argv().address
    )
}

length(.self: &Arguments) -> (.count: UIntNative) := {
    count = self&.count
}

has_argument(
        .self  : &Arguments,
        .index : UIntNative,
    ) -> (
        .ok : Bool
    ) := {
    ok = index < self&.count
}

argument_pointer_address(
        .self  : &Arguments,
        .index : UIntNative,
    ) -> (
        .address : UIntNative
    ) := {
    stride :: UIntNative = size_of(.type = UIntNative)
    address = self&.address + index * stride
}

argument_at(
        .self  : &Arguments,
        .index : UIntNative,
    ) -> (
        .text : &Char
    ) := {
    addr ::= argument_pointer_address(self, .index = index).address
    raw ::= raw_pointer#(.t: UIntNative)(.address = addr)
    ptr ::= trusted_establish_inherited_reference#(.t: UIntNative)(
        .raw  = raw
        .root = erase_reference#(.t: Arguments)(.base = self).reference
    ).reference
    text_address ::= ptr&
    text_raw ::= raw_pointer#(.t: Char)(.address = text_address)
    inherited ::= trusted_establish_inherited_reference#(.t: Char)(
        .raw  = text_raw
        .root = erase_reference#(.t: Arguments)(.base = self).reference
    ).reference
    text = read_reference#(.t: Char)(.base = inherited).reference
}

argument_view_at(
        .self  : &Arguments,
        .index : UIntNative,
    ) -> (
        .view : StringView
    ) := {
    assume ffi := self&._ffi
    text ::= argument_at(self, .index = index)
    view = (
        .data   = trusted_reinterpret_reference#(.from: Char, .to: UInt8)(.base = text).reference
        .length = strlen(.string = text).length
    )
}

get(
        .self  : &Arguments,
        .index : UIntNative,
    ) -> (
        .result : Errable#(StringView, (..out_of_bounds))
    ) := {
    if index >= self&.count {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    result = ..ok argument_view_at(self, .index = index)
}

to_iterator(
        .value : &Arguments,
    ) -> (
        .iterator : ArgumentsIterator
    ) := {
    iterator = (
        .args  = value
        .index = 0
    )
}

has_next(
        .self : &ArgumentsIterator,
    ) -> (
        .ok : Bool
    ) := {
    ok = self&.index < self&.args&.count
}

next(
        .self : $&ArgumentsIterator,
    ) -> (
        .value : StringView
    ) := {
    current_index :: UIntNative = self&.index
    value = argument_view_at(self&.args, .index = current_index)
    self&= (
        .args  = self&.args
        .index = current_index + 1
    )
}
