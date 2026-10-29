-- Borrowed views over proven contiguous initialized storage. Permissions
-- describe access through this handle; neither view owns or freezes the values.
-- Private references and lengths must describe the same live region.
ArrayView := #(.t: Type) (
    ._data   : ?&t
    ._length : UIntNative
)

MutableArrayView := #(.t: Type) (
    ._data   : ?$&t
    ._length : UIntNative
)

implement#(.t: Type) ImplicitlyCopyable#(MutableArrayView#(.t: t)) ()

implement#(.t: Type) ImplicitlyCopyable#(ArrayView#(.t: t)) ()

_mutable_array_view_data := #(.t: Type) (.self: &MutableArrayView#(.t: t)) -> (.pointer: $&t) {
    match self&._data {
        ..none { abort }
        ..some payload { pointer = payload.value }
    }
}

_array_view_data := #(.t: Type) (.self: &ArrayView#(.t: t)) -> (.pointer: &t) {
    match self&._data {
        ..none { abort }
        ..some payload { pointer = payload.value }
    }
}

-- Empty views need no backing reference and remain independent of storage.
empty_array_view := #(.t: Type) () -> (.array: ArrayView#(.t: t)) {
    array = (._data = ..none, ._length = 0)
}

single_array_view := #(.t: Type) (.data: &t) -> (.array: ArrayView#(.t: t)) {
    array = (._data = ..some(.value = data), ._length = 1)
}

single_mutable_array_view := #(.t: Type) (.data: $&t) -> (.array: MutableArrayView#(.t: t)) {
    array = (._data = ..some(.value = data), ._length = 1)
}

_fixed_array_view := #(.n: UIntNative, .t: Type) (.array: &Array#(.n = n, .t: t)) -> (
    .view : ArrayView#(.t: t)
) {
    if n == 0 {
        view = (._data = ..none, ._length = 0)
        return
    }

    first ::= trusted_reinterpret_reference#(.from: Array#(.n = n, .t: t), .to: t)(
        .base = array
    ).reference
    view = (._data = ..some(.value = first), ._length = n)
}

_fixed_mutable_array_view := #(.n: UIntNative, .t: Type) (.array: $&Array#(.n = n, .t: t)) -> (
    .view : MutableArrayView#(.t: t)
) {
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
-- Core callers must prove the requested contiguous range belongs to the
-- live backing storage and initialize an element before reading it.
_trusted_array_view := #(.t: Type) (.data: &t, .length: UIntNative) -> (
    .array : ArrayView#(.t: t)
) {
    if length == 0 {
        array = (._data = ..none, ._length = 0)
        return
    }

    array = (._data = ..some(.value = data), ._length = length)
}

_trusted_mutable_array_view := #(.t: Type) (.data: $&t, .length: UIntNative) -> (
    .array : MutableArrayView#(.t: t)
) {
    if length == 0 {
        array = (._data = ..none, ._length = 0)
        return
    }

    array = (
        ._data   = ..some(.value = data)
        ._length = length
    )
}

set := #(.t: Type: ImplicitlyCopyable) (
    .self         : $&MutableArrayView#(.t: t),
    .index        : UIntNative,
    .value        : t,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Void, (..out_of_bounds))) {
    assume error_tracer

    if index >= self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    ptr ::= trusted_mutable_reference_offset#(.t: t)(
        .base = data(self).pointer, .elements = index
    )
    ptr&= value

    result = ..ok Void()
}

as_readonly := #(.t: Type) (.self: &MutableArrayView#(.t: t)) -> (.view: ArrayView#(.t: t)) {
    if self&._length == 0 {
        view = empty_array_view#(.t: t)().array
        return
    }

    first ::= read_reference#(.t: t)(.base = data(self).pointer).reference
    view = _trusted_array_view#(.t: t)(.data = first, .length = self&._length).array
}

implement#(.t: Type) Indexable#(MutableArrayView#(.t: t)) (
    .Item : Type = t

    .length = (.self: &MutableArrayView#(.t: t)) -> (.count: UIntNative) {
        count = self&._length
    }

    .get_reference = (
        .self         : &MutableArrayView#(.t: t),
        .index        : UIntNative,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(&t, (..out_of_bounds))) {
        assume error_tracer

        if index >= self&._length {
            result = ..error(.reason = ..out_of_bounds)
            return
        }

        result = ..ok trusted_reference_offset#(.t: t)(
            .base = data(self).pointer, .elements = index
        ).reference
    }
)

implement#(.t: Type) Indexable#(ArrayView#(.t: t)) (
    .Item : Type = t

    .length = (.self: &ArrayView#(.t: t)) -> (.count: UIntNative) {
        count = self&._length
    }

    .get_reference = (
        .self         : &ArrayView#(.t: t),
        .index        : UIntNative,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(&t, (..out_of_bounds))) {
        assume error_tracer

        if index >= self&._length {
            result = ..error(.reason = ..out_of_bounds)
            return
        }

        result = ..ok trusted_reference_offset#(.t: t)(
            .base = data(self).pointer, .elements = index
        ).reference
    }
)

implement#(.t: Type) MutableIndexable#(MutableArrayView#(.t: t)) (
    .Item : Type = t

    .get_mutable_reference = (
        .self         : $&MutableArrayView#(.t: t),
        .index        : UIntNative,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#($&t, (..out_of_bounds))) {
        assume error_tracer

        if index >= self&._length {
            result = ..error(.reason = ..out_of_bounds)
            return
        }

        result = ..ok trusted_mutable_reference_offset#(.t: t)(
            .base = data(self).pointer, .elements = index
        ).reference
    }
)

implement#(.t: Type: ImplicitlyCopyable) IndexableValue#(MutableArrayView#(.t: t)) (
    .Item : Type = t

    .get = (
        .self         : &MutableArrayView#(.t: t),
        .index        : UIntNative,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(t, (..out_of_bounds))) {
        assume error_tracer

        if index >= self&._length {
            result = ..error(.reason = ..out_of_bounds)
            return
        }

        ptr ::= trusted_reference_offset#(.t: t)(
            .base = data(self).pointer, .elements = index
        ).reference

        result = ..ok ptr&
    }
)

implement#(.t: Type: ImplicitlyCopyable) IndexableValue#(ArrayView#(.t: t)) (
    .Item : Type = t

    .get = (
        .self         : &ArrayView#(.t: t),
        .index        : UIntNative,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(t, (..out_of_bounds))) {
        assume error_tracer

        match get_reference(self, .index = index).result {
            ..error _ { result = ..error(.reason = ..out_of_bounds) }
            ..ok pointer { result = ..ok pointer&}
        }
    }
)
