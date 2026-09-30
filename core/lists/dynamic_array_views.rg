-- Reinitialize the marker Place so existing temporal summaries invalidate
-- old shape-dependent aliases. No runtime epoch comparison is required.
_invalidate_dynamic_array_shape#(.t: Type)(.array: $&DynamicArray#(.t: t)) -> () := {
    shape ::= $&array&._shape
    deinit(.self = shape)
    shape& = (.marker = 0)
}

-- The collection owns a private allocation receipt and an initialized prefix.
-- Only that prefix is exposed; spare capacity never becomes readable storage.
-- Borrowed element facts retain the backing allocation's temporal generation.
array_view#(.t: Type)(
    .array: $&DynamicArray#(.t: t),
) -> (.view: ArrayView#(.t: t)) := {
    if array&._length == 0 {
        view = (._data = ..none, ._length = 0)
        return
    }
    first ::= _trusted_dynamic_array_element_rw_pointer#(.t: t)(.array = array, .offset = 0).pointer
    borrowed ::= depend_on#(.t: $&t)(.value = first, .on = erase_reference#(.t: _DynamicArrayShape)(.base = &array&._shape).reference).result
    view = _trusted_array_view#(.t: t)(.data = borrowed, .length = array&._length).array
}

array_view_ro#(.t: Type)(
    .array: &DynamicArray#(.t: t),
) -> (.view: ArrayViewRO#(.t: t)) := {
    if array&._length == 0 {
        view = (._data = ..none, ._length = 0)
        return
    }
    first ::= _trusted_dynamic_array_element_ro_pointer#(.t: t)(.array = array, .offset = 0).pointer
    borrowed ::= depend_on#(.t: &t)(.value = first, .on = erase_reference#(.t: _DynamicArrayShape)(.base = &array&._shape).reference).result
    view = _trusted_array_view_ro#(.t: t)(.data = borrowed, .length = array&._length).array
}

-- Public element loans share the collection's structural invalidation rule.
-- Internal opaque transfers use private pointers without a shape dependency.
dynamic_array_element_ro_pointer#(.t: Type)(
    .array: &DynamicArray#(.t: t), .offset: UIntNative,
) -> (.pointer: &t) := {
    element ::= _trusted_dynamic_array_element_ro_pointer#(.t: t)(.array = array, .offset = offset).pointer
    pointer = depend_on#(.t: &t)(.value = element, .on = erase_reference#(.t: _DynamicArrayShape)(.base = &array&._shape).reference).result
}

dynamic_array_element_rw_pointer#(.t: Type)(
    .array: $&DynamicArray#(.t: t), .offset: UIntNative,
) -> (.pointer: $&t) := {
    element ::= _trusted_dynamic_array_element_rw_pointer#(.t: t)(.array = array, .offset = offset).pointer
    pointer = depend_on#(.t: $&t)(.value = element, .on = erase_reference#(.t: _DynamicArrayShape)(.base = &array&._shape).reference).result
}
