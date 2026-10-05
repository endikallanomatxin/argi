-- A subrange is justified by an existing view, not by an arbitrary pointer
-- and claimed length. Subtraction after checking start avoids range-sum wrap.
slice#(
        .t : Type
    )(
        .self  : &ArrayView#(.t: t),
        .start : UIntNative,
        .count : UIntNative,
    ) -> (
        .result : Errable#(ArrayView#(.t: t), (..out_of_bounds))
    ) := {
    if start > self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    if count > self&._length - start {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    if count == 0 {
        result = ..ok(._data = ..none, ._length = 0)
        return
    }

    first ::= trusted_mutable_reference_offset#(.t: t)(
        .base     = data#(.t: t)(self).pointer
        .elements = start
    ).reference

    result = ..ok _trusted_array_view#(.t: t)(.data = first, .length = count).array
}

slice#(
        .t : Type
    )(
        .self  : &ArrayViewRO#(.t: t),
        .start : UIntNative,
        .count : UIntNative,
    ) -> (
        .result : Errable#(ArrayViewRO#(.t: t), (..out_of_bounds))
    ) := {
    if start > self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    if count > self&._length - start {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    if count == 0 {
        result = ..ok(._data = ..none, ._length = 0)
        return
    }

    first ::= trusted_reference_offset#(.t: t)(
        .base     = data#(.t: t)(self).pointer
        .elements = start
    ).reference

    result = ..ok _trusted_array_view_ro#(.t: t)(.data = first, .length = count).array
}
