-- Iterators retain the initialized extent and lifetime of a borrowed view.
-- Cursor updates preserve that loan; collection shape changes invalidate it.
DynamicArrayIterator#(.t: Type): Type = (
    ._view  : ArrayView#(.t: t)
    ._index : UIntNative
)

DynamicArrayReferenceIterator#(.t: Type): Type = (
    ._view  : ArrayView#(.t: t)
    ._index : UIntNative
)

DynamicArrayMutableReferenceIterator#(.t: Type): Type = (
    ._view  : MutableArrayView#(.t: t)
    ._index : UIntNative
)

implement#(.t: Type: ImplicitlyCopyable) Iterable#(DynamicArray#(.t: t)) (
    .Item         : Type = t
    .IteratorType : Type = DynamicArrayIterator#(.t: t)

    .to_iterator = (.value: &DynamicArray#(.t: t)) -> (.iterator: DynamicArrayIterator#(.t: t)) {
        iterator = (._view = view(.array = value), ._index = 0)
    }
)

implement#(.t: Type) ReferenceIterable#(DynamicArray#(.t: t)) (
    .Item         : Type = t
    .IteratorType : Type = DynamicArrayReferenceIterator#(.t: t)

    .to_reference_iterator = (.value: &DynamicArray#(.t: t)) -> (
        .iterator : DynamicArrayReferenceIterator#(.t: t)
    ) {
        iterator = (._view = view(.array = value), ._index = 0)
    }
)

implement#(.t: Type) MutableReferenceIterable#(DynamicArray#(.t: t)) (
    .Item         : Type = t
    .IteratorType : Type = DynamicArrayMutableReferenceIterator#(.t: t)

    .to_mutable_reference_iterator = (.value: $&DynamicArray#(.t: t)) -> (
        .iterator : DynamicArrayMutableReferenceIterator#(.t: t)
    ) {
        iterator = (._view = view(.array = value), ._index = 0)
    }
)

implement#(.t: Type: ImplicitlyCopyable) Iterator#(DynamicArrayIterator#(.t: t)) (
    .Item : Type = t

    .has_next = (.self: &DynamicArrayIterator#(.t: t)) -> (.ok: Bool) {
        ok = self&._index < length(&self&._view).count
    }

    .next = (.self: $&DynamicArrayIterator#(.t: t)) -> (.value: t) {
        -- Value iteration is the array's conditional implicit-copy capability.
        current_index :: UIntNative = self&._index

        if current_index >= self&._view._length { abort }
        ptr ::= trusted_reference_offset#(.t: t)(
            .base = data(&self&._view).pointer, .elements = current_index
        ).reference
        value = ptr&
        self&._index = current_index + 1
    }
)

implement#(.t: Type) Iterator#(DynamicArrayReferenceIterator#(.t: t)) (
    .Item : Type = &t

    .has_next = (.self: &DynamicArrayReferenceIterator#(.t: t)) -> (.ok: Bool) {
        ok = self&._index < length(&self&._view).count
    }

    .next = (.self: $&DynamicArrayReferenceIterator#(.t: t)) -> (.value: &t) {
        current_index :: UIntNative = self&._index

        if current_index >= self&._view._length { abort }
        value = trusted_reference_offset#(.t: t)(
            .base = data(&self&._view).pointer, .elements = current_index
        ).reference
        self&._index = current_index + 1
    }
)

implement#(.t: Type) Iterator#(DynamicArrayMutableReferenceIterator#(.t: t)) (
    .Item : Type = $&t

    .has_next = (.self: &DynamicArrayMutableReferenceIterator#(.t: t)) -> (.ok: Bool) {
        ok = self&._index < length(&self&._view).count
    }

    .next = (.self: $&DynamicArrayMutableReferenceIterator#(.t: t)) -> (.value: $&t) {
        current_index :: UIntNative = self&._index

        if current_index >= self&._view._length { abort }
        value = trusted_mutable_reference_offset#(.t: t)(
            .base = data(&self&._view).pointer, .elements = current_index
        ).reference
        self&._index = current_index + 1
    }
)
