ArrayView#(.t: Type): Type = (
    --
    -- Non-owning view over a contiguous initialized region of elements.
    -- Empty views carry no element reference; data() requires a nonempty view.
    --
    -- The pointer and length must describe the same live region. Ordinary
    -- constructors derive the length from a referenced object; raw storage
    -- requires an explicit trusted boundary.
    --
    ._data   : ?$&t
    ._length : UIntNative
)

ArrayViewRO#(.t: Type): Type = (
    ._data   : ?&t
    ._length : UIntNative
)

ArrayView#(.t: Type) implements ImplicitlyCopyable
ArrayViewRO#(.t: Type) implements ImplicitlyCopyable

length#(.t: Type)(.self: &ArrayView#(.t: t)) -> (.count: UIntNative) := {
    count = self&._length
}

length#(.t: Type)(.self: &ArrayViewRO#(.t: t)) -> (.count: UIntNative) := {
    count = self&._length
}

data#(.t: Type)(.self: &ArrayView#(.t: t)) -> (.pointer: $&t) := {
    match self&._data {
        ..none { abort }
        ..some payload { pointer = payload.value }
    }
}

data#(.t: Type)(.self: &ArrayViewRO#(.t: t)) -> (.pointer: &t) := {
    match self&._data {
        ..none { abort }
        ..some payload { pointer = payload.value }
    }
}

-- Empty views need no backing reference and remain independent of storage.
array_view_ro#(.t: Type)() -> (.array: ArrayViewRO#(.t: t)) := {
    array = (._data = ..none, ._length = 0)
}

array_view_ro#(.t: Type)(.data: &t) -> (.array: ArrayViewRO#(.t: t)) := {
    array = (._data = ..some(.value = data), ._length = 1)
}

array_view#(.t: Type)(.data: $&t) -> (.array: ArrayView#(.t: t)) := {
    array = (._data = ..some(.value = data), ._length = 1)
}

array_view_ro#(
        .n : UIntNative,
        .t : Type
    )(
        .array : &Array#(.n = n, .t: t),
    ) -> (
        .view : ArrayViewRO#(.t: t)
    ) := {
    if n == 0 {
        view = (._data = ..none, ._length = 0)
        return
    }

    first ::= trusted_reinterpret_reference#(.from: Array#(.n = n, .t: t), .to: t)(.base = array).reference
    view = (._data = ..some(.value = first), ._length = n)
}

array_view#(
        .n : UIntNative,
        .t : Type
    )(
        .array : $&Array#(.n = n, .t: t),
    ) -> (
        .view : ArrayView#(.t: t)
    ) := {
    if n == 0 {
        view = (._data = ..none, ._length = 0)
        return
    }

    first ::= trusted_mutable_reinterpret_reference#(.from: Array#(.n = n, .t: t), .to: t)(
        .base = array
    ).reference
    view = (._data = ..some(.value = first), ._length = n)
}

-- Reference mutability selects a writable or read-only view. Both forms
-- derive the extent from the array and retain its validity dependencies.
view#(.n: UIntNative, .t: Type)(.array: $&Array#(.n = n, .t: t)) -> (.result: ArrayView#(.t: t)) := {
    result = array_view(.array = array)
}

view#(.n: UIntNative, .t: Type)(.array: &Array#(.n = n, .t: t)) -> (.result: ArrayViewRO#(.t: t)) := {
    result = array_view_ro(.array = array)
}

-- Core callers must prove the requested contiguous range belongs to the
-- live backing storage and initialize an element before reading it.
_trusted_array_view_ro#(.t: Type)(.data: &t, .length: UIntNative) -> (.array: ArrayViewRO#(.t: t)) := {
    if length == 0 {
        array = (._data = ..none, ._length = 0)
        return
    }

    array = (._data = ..some(.value = data), ._length = length)
}

_trusted_array_view#(
        .t : Type
    )(
        .data   : $&t,
        .length : UIntNative,
    ) -> (
        .array : ArrayView#(.t: t)
    ) := {
    if length == 0 {
        array = (._data = ..none, ._length = 0)
        return
    }

    array = (
        ._data   = ..some(.value = data)
        ._length = length
    )
}

get_ro_ref#(
        .t : Type
    )(
        .self  : &ArrayView#(.t: t),
        .index : UIntNative,
    ) -> (
        .result : Errable#(&t, (..out_of_bounds))
    ) := {
    if index >= self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    result = ..ok trusted_reference_offset#(.t: t)(
        .base     = data#(.t: t)(.self = self).pointer
        .elements = index
    ).reference
}

get_ro_ref#(
        .t : Type
    )(
        .self  : &ArrayViewRO#(.t: t),
        .index : UIntNative,
    ) -> (
        .result : Errable#(&t, (..out_of_bounds))
    ) := {
    if index >= self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    result = ..ok trusted_reference_offset#(.t: t)(
        .base     = data#(.t: t)(.self = self).pointer
        .elements = index
    ).reference
}

get_rw_ref#(
        .t : Type
    )(
        .self  : $&ArrayView#(.t: t),
        .index : UIntNative,
    ) -> (
        .result : Errable#($&t, (..out_of_bounds))
    ) := {
    if index >= self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    result = ..ok trusted_mutable_reference_offset#(.t: t)(
        .base     = data#(.t: t)(.self = self).pointer
        .elements = index
    ).reference
}

get#(
        .t : Type: ImplicitlyCopyable
    )(
        .self  : &ArrayView#(.t: t),
        .index : UIntNative,
    ) -> (
        .result : Errable#(t, (..out_of_bounds))
    ) := {
    if index >= self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    ptr ::= trusted_reference_offset#(.t: t)(
        .base     = data#(.t: t)(.self = self).pointer
        .elements = index
    ).reference

    result = ..ok ptr&
}

set#(
        .t : Type: ImplicitlyCopyable
    )(
        .self  : $&ArrayView#(.t: t),
        .index : UIntNative,
        .value : t,
    ) -> (
        .result : Errable#(Void, (..out_of_bounds))
    ) := {
    if index >= self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    ptr ::= trusted_mutable_reference_offset#(.t: t)(
        .base     = data#(.t: t)(.self = self).pointer
        .elements = index
    )
    ptr&= value

    result = ..ok Void()
}

ArrayView#(.t: Type) implements Indexable#(.t: t)
ArrayViewRO#(.t: Type) implements Indexable#(.t: t)
ArrayView#(.t: Type) implements IndexableMutable#(.t: t)
ArrayView#(.t: Type: ImplicitlyCopyable) implements IndexableValue#(.t: t)
ArrayViewRO#(.t: Type: ImplicitlyCopyable) implements IndexableValue#(.t: t)

get#(
        .t : Type: ImplicitlyCopyable
    )(
        .self  : &ArrayViewRO#(.t: t),
        .index : UIntNative,
    ) -> (
        .result : Errable#(t, (..out_of_bounds))
    ) := {
    match get_ro_ref#(.t: t)(.self = self, .index = index).result {
        ..error _ { result = ..error(.reason = ..out_of_bounds) }
        ..ok pointer { result = ..ok pointer&}
    }
}

as_readonly#(.t: Type)(.self: &ArrayView#(.t: t)) -> (.view: ArrayViewRO#(.t: t)) := {
    if self&._length == 0 {
        view = array_view_ro#(.t: t)().array
        return
    }

    first ::= read_reference#(.t: t)(.base = data(.self = self).pointer).reference
    view = _trusted_array_view_ro#(.t: t)(.data = first, .length = self&._length).array
}
