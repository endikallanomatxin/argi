-- Iterators retain the initialized extent and lifetime of a borrowed view.
-- Cursor updates preserve that loan; collection shape changes invalidate it.
DynamicArrayIterator#(.t: Type): Type = (
    ._view  : ArrayViewRO#(.t: t)
    ._index : UIntNative
)

DynamicArrayROPointerIterator#(.t: Type): Type = (
    ._view  : ArrayViewRO#(.t: t)
    ._index : UIntNative
)

DynamicArrayRWPointerIterator#(.t: Type): Type = (
    ._view  : ArrayView#(.t: t)
    ._index : UIntNative
)

DynamicArrayIterator#(.t: Type: ImplicitlyCopyable) implements Iterator#(.t: t)
DynamicArrayROPointerIterator#(.t: Type) implements Iterator#(.t: &t)
DynamicArrayRWPointerIterator#(.t: Type) implements Iterator#(.t: $&t)
DynamicArray#(.t: Type: ImplicitlyCopyable) implements Iterable#(.t: t)
DynamicArray#(.t: Type) implements ROPointerIterable#(.t: t)
DynamicArray#(.t: Type) implements RWPointerIterable#(.t: t)

to_iterator#(
        .t : Type: ImplicitlyCopyable
    )(
        .value : &DynamicArray#(.t: t)
    ) -> (
        .iterator : DynamicArrayIterator#(.t: t)
    ) := {
    iterator = (
        ._view  = array_view_ro#(.t: t)(.array = value).view
        ._index = 0
    )
}

to_ro_pointer_iterator#(
        .t : Type
    )(
        .value : &DynamicArray#(.t: t)
    ) -> (
        .iterator : DynamicArrayROPointerIterator#(.t: t)
    ) := {
    iterator = (
        ._view  = array_view_ro#(.t: t)(.array = value).view
        ._index = 0
    )
}

to_rw_pointer_iterator#(
        .t : Type
    )(
        .value : $&DynamicArray#(.t: t)
    ) -> (
        .iterator : DynamicArrayRWPointerIterator#(.t: t)
    ) := {
    iterator = (
        ._view  = array_view#(.t: t)(.array = value).view
        ._index = 0
    )
}

has_next#(
        .t : Type: ImplicitlyCopyable
    )(
        .self : &DynamicArrayIterator#(.t: t)
    ) -> (
        .ok : Bool
    ) := {
    ok = self&._index < length#(.t: t)(.self = &self&._view).count
}

next#(
        .t : Type: ImplicitlyCopyable
    )(
        .self : $&DynamicArrayIterator#(.t: t)
    ) -> (
        .value : t
    ) := {
    -- Value iteration is the array's conditional implicit-copy capability.
    current_index :: UIntNative = self&._index

    if current_index >= self&._view._length { abort }
    ptr ::= trusted_reference_offset#(.t: t)(
        .base     = data#(.t: t)(.self = &self&._view).pointer
        .elements = current_index
    ).reference
    value = ptr&
    self&._index = current_index + 1
}

has_next#(
        .t : Type
    )(
        .self : &DynamicArrayROPointerIterator#(.t: t)
    ) -> (
        .ok : Bool
    ) := {
    ok = self&._index < length#(.t: t)(.self = &self&._view).count
}

next#(
        .t : Type
    )(
        .self : $&DynamicArrayROPointerIterator#(.t: t)
    ) -> (
        .value : &t
    ) := {
    current_index :: UIntNative = self&._index

    if current_index >= self&._view._length { abort }
    value = trusted_reference_offset#(.t: t)(
        .base     = data#(.t: t)(.self = &self&._view).pointer
        .elements = current_index
    ).reference
    self&._index = current_index + 1
}

has_next#(
        .t : Type
    )(
        .self : &DynamicArrayRWPointerIterator#(.t: t)
    ) -> (
        .ok : Bool
    ) := {
    ok = self&._index < length#(.t: t)(.self = &self&._view).count
}

next#(
        .t : Type
    )(
        .self : $&DynamicArrayRWPointerIterator#(.t: t)
    ) -> (
        .value : $&t
    ) := {
    current_index :: UIntNative = self&._index

    if current_index >= self&._view._length { abort }
    value = trusted_mutable_reference_offset#(.t: t)(
        .base     = data#(.t: t)(.self = &self&._view).pointer
        .elements = current_index
    ).reference
    self&._index = current_index + 1
}
