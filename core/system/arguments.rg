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

once _acquire_arguments := (.args: (.ffi: $&ForeignFunctionInterface = reach ffi)) -> (
    .result : Arguments
) {
    assume ffi := args.ffi

    result = (
        ._ffi    = ffi
        .count   = argi_runtime_argc().count
        .address = argi_runtime_argv().address
    )
}

implement Init#(Arguments, (.ffi: $&ForeignFunctionInterface = reach ffi)) (
    .Result : Type = Arguments
    .init   = _acquire_arguments
)

has_argument(.self: &Arguments, .index: UIntNative) -> (.ok: Bool) := {
    ok = index < self&.count
}

argument_pointer_address(.self: &Arguments, .index: UIntNative) -> (.address: UIntNative) := {
    stride :: UIntNative = size_of(.type = UIntNative)
    address = self&.address + index * stride
}

argument_at(.self: &Arguments, .index: UIntNative) -> (.text: &Char) := {
    addr ::= argument_pointer_address(self, .index = index).address
    raw ::= raw_pointer#(.t: UIntNative)(.address = addr)
    ptr ::= trusted_establish_inherited_reference#(.t: UIntNative)(
        .raw = raw, .root = erase_reference#(.t: Arguments)(.base = self).reference
    ).reference
    text_address ::= ptr&
    text_raw ::= raw_pointer#(.t: Char)(.address = text_address)
    inherited ::= trusted_establish_inherited_reference#(.t: Char)(
        .raw = text_raw, .root = erase_reference#(.t: Arguments)(.base = self).reference
    ).reference
    text = read_reference#(.t: Char)(.base = inherited).reference
}

argument_view_at(.self: &Arguments, .index: UIntNative) -> (
    .result : Errable#(StringView, (..out_of_bounds, ..invalid_utf8))
) := {
    if index >= self&.count {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    assume ffi := self&._ffi
    text ::= argument_at(self, .index = index)
    bytes ::= _c_string_bytes(.text = text)
    _ ::= validate_utf8_bytes(.bytes = bytes)!
    result = ..ok _trusted_c_string_view(.text = text)
}

implement Iterable#(Arguments) (
    .Item         : Type = StringView
    .IteratorType : Type = ArgumentsIterator

    .to_iterator = (.value: &Arguments) -> (.iterator: ArgumentsIterator) {
        iterator = (.args = value, .index = 0)
    }
)

implement Iterator#(ArgumentsIterator) (
    .Item : Type = StringView

    .has_next = (.self: &ArgumentsIterator) -> (.ok: Bool) {
        ok = self&.index < self&.args&.count
    }

    .next = (.self: $&ArgumentsIterator) -> (.value: StringView) {
        assume error_tracer ::= $&noop_error_tracer
        current_index :: UIntNative = self&.index
        match argument_view_at(self&.args, .index = current_index) {
            ..ok text { value = text }
            ..error _ { abort }
        }
        self&= (.args = self&.args, .index = current_index + 1)
    }
)

implement ArgumentSource#(Arguments) (
    .length = (.self: &Arguments) -> (.count: UIntNative) {
        count = self&.count
    }

    .get = (.self: &Arguments, .index: UIntNative) -> (
        .result : Errable#(StringView, (..out_of_bounds, ..invalid_utf8))
    ) {
        if index >= self&.count {
            result = ..error(.reason = ..out_of_bounds)
            return
        }

        result = argument_view_at(self, .index = index)
    }
)
