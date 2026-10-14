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

implement#(
        .t : Type: ImplicitlyCopyable
    ) Iterable#(DynamicArray#(.t: t)) (
    .Item: Type = t
    .IteratorType: Type = DynamicArrayIterator#(.t: t)

    .to_iterator = (
            .value : &DynamicArray#(.t: t)
        ) -> (
            .iterator : DynamicArrayIterator#(.t: t)
        ) {
        iterator = (
            ._view  = view(.array = value)
            ._index = 0
        )
    }
)

implement#(
        .t : Type
    ) ROPointerIterable#(DynamicArray#(.t: t)) (
    .Item: Type = t
    .IteratorType: Type = DynamicArrayROPointerIterator#(.t: t)

    .to_ro_pointer_iterator = (
            .value : &DynamicArray#(.t: t)
        ) -> (
            .iterator : DynamicArrayROPointerIterator#(.t: t)
        ) {
        iterator = (
            ._view  = view(.array = value)
            ._index = 0
        )
    }
)

implement#(
        .t : Type
    ) RWPointerIterable#(DynamicArray#(.t: t)) (
    .Item: Type = t
    .IteratorType: Type = DynamicArrayRWPointerIterator#(.t: t)

    .to_rw_pointer_iterator = (
            .value : $&DynamicArray#(.t: t)
        ) -> (
            .iterator : DynamicArrayRWPointerIterator#(.t: t)
        ) {
        iterator = (
            ._view  = view(.array = value)
            ._index = 0
        )
    }
)

implement#(
        .t : Type: ImplicitlyCopyable
    ) Iterator#(DynamicArrayIterator#(.t: t)) (
    .Item: Type = t

    .has_next = (
            .self : &DynamicArrayIterator#(.t: t)
        ) -> (
            .ok : Bool
        ) {
        ok = self&._index < length(&self&._view).count
    }

    .next = (
            .self : $&DynamicArrayIterator#(.t: t)
        ) -> (
            .value : t
        ) {
        -- Value iteration is the array's conditional implicit-copy capability.
        current_index :: UIntNative = self&._index

        if current_index >= self&._view._length { abort }
        ptr ::= trusted_reference_offset#(.t: t)(
            .base     = data#(.t: t)(&self&._view).pointer
            .elements = current_index
        ).reference
        value = ptr&
        self&._index = current_index + 1
    }
)

implement#(
        .t : Type
    ) Iterator#(DynamicArrayROPointerIterator#(.t: t)) (
    .Item: Type = &t

    .has_next = (
            .self : &DynamicArrayROPointerIterator#(.t: t)
        ) -> (
            .ok : Bool
        ) {
        ok = self&._index < length(&self&._view).count
    }

    .next = (
            .self : $&DynamicArrayROPointerIterator#(.t: t)
        ) -> (
            .value : &t
        ) {
        current_index :: UIntNative = self&._index

        if current_index >= self&._view._length { abort }
        value = trusted_reference_offset#(.t: t)(
            .base     = data#(.t: t)(&self&._view).pointer
            .elements = current_index
        ).reference
        self&._index = current_index + 1
    }
)

implement#(
        .t : Type
    ) Iterator#(DynamicArrayRWPointerIterator#(.t: t)) (
    .Item: Type = $&t

    .has_next = (
            .self : &DynamicArrayRWPointerIterator#(.t: t)
        ) -> (
            .ok : Bool
        ) {
        ok = self&._index < length(&self&._view).count
    }

    .next = (
            .self : $&DynamicArrayRWPointerIterator#(.t: t)
        ) -> (
            .value : $&t
        ) {
        current_index :: UIntNative = self&._index

        if current_index >= self&._view._length { abort }
        value = trusted_mutable_reference_offset#(.t: t)(
            .base     = data#(.t: t)(&self&._view).pointer
            .elements = current_index
        ).reference
        self&._index = current_index + 1
    }
)
