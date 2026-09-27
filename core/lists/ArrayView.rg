ArrayView#(.t: Type) : Type = (
    --
    -- Non-owning view over a contiguous mutable region of elements.
    --
    -- This is a general core descriptor. Interop layers can lower it to the
    -- concrete ABI shape a foreign boundary expects, but the language-level
    -- concept is simply a mutable `pointer + length` view.
    --
    .data   : $&t
    .length : UIntNative
)

ArrayViewRO#(.t: Type) : Type = (
    .data   : &t
    .length : UIntNative
)

ArrayView#(.t: Type) implements ImplicitlyCopyable
ArrayViewRO#(.t: Type) implements ImplicitlyCopyable

length#(.t: Type)(.self: &ArrayView#(.t: t)) -> (.count: UIntNative) := {
    count = self&.length
}

length#(.t: Type)(.self: &ArrayViewRO#(.t: t)) -> (.count: UIntNative) := {
    count = self&.length
}

array_view_ro#(.t: Type)(.data: &t, .length: UIntNative) -> (.array: ArrayViewRO#(.t: t)) := {
    array = (.data = data, .length = length)
}

array_view#(.t: Type)(
    .data: $&t,
    .length: UIntNative,
) -> (.array: ArrayView#(.t: t)) := {
    -- The caller must supply a contiguous, initialized range of this length.
    -- TODO: carry allocation bounds into view construction so this precondition
    -- can be enforced for callers outside trusted low-level code.
    array = (
        .data = data,
        .length = length,
    )
}

array_view_from_raw#(.t: Type)(
    .raw: RawPointer#(.t: t),
    .root: $&Any,
    .length: UIntNative,
) -> (.array: ArrayView#(.t: t)) := {
    data ::= establish_inherited_reference#(.t: t)(.raw = raw, .root = root)
    array = array_view#(.t: t)(.data = data, .length = length)
}

get_ro_ref#(.t: Type)(
    .self: &ArrayView#(.t: t),
    .index: UIntNative,
) -> (.result: Errable#(.t: &t, .reasons: (..out_of_bounds))) := {
    if index >= self&.length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    result = ..ok reference_offset#(.t: t)(.base = self&.data, .elements = index).reference
}

get_ro_ref#(.t: Type)(
    .self: &ArrayViewRO#(.t: t),
    .index: UIntNative,
) -> (.result: Errable#(.t: &t, .reasons: (..out_of_bounds))) := {
    if index >= self&.length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    result = ..ok reference_offset#(.t: t)(.base = self&.data, .elements = index).reference
}

get_rw_ref#(.t: Type)(
    .self: $&ArrayView#(.t: t),
    .index: UIntNative,
) -> (.result: Errable#(.t: $&t, .reasons: (..out_of_bounds))) := {
    if index >= self&.length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    result = ..ok mutable_reference_offset#(.t: t)(.base = self&.data, .elements = index).reference
}

get#(.t: Type: ImplicitlyCopyable)(
    .self: &ArrayView#(.t: t),
    .index: UIntNative,
) -> (.result: Errable#(.t: t, .reasons: (..out_of_bounds))) := {
    if index >= self&.length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    ptr ::= reference_offset#(.t: t)(.base = self&.data, .elements = index).reference
    result = ..ok ptr&
}

set#(.t: Type: ImplicitlyCopyable)(
    .self: $&ArrayView#(.t: t),
    .index: UIntNative,
    .value: t,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_bounds))) := {
    if index >= self&.length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    ptr ::= mutable_reference_offset#(.t: t)(.base = self&.data, .elements = index)
    ptr& = value
    result = ..ok Void()
}
