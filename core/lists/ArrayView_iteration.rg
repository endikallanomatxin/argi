-- Iterators retain the initialized extent and lifetime of a borrowed view.
-- Cursor updates preserve that loan; collection shape changes invalidate it.
implement#(.t: Type: ImplicitlyCopyable) Iterable#(ArrayView#(t)) (
    .Item         : Type = t
    .IteratorType : Type = ArrayViewIterator#(t)
    .to_iterator  = (.value: &ArrayView#(t)) -> (.iterator: IteratorType) {
        iterator = (._view = value&, ._index = 0)
    }
)

implement#(.t: Type) ReferenceIterable#(ArrayView#(t)) (
    .Item                  : Type = t
    .IteratorType          : Type = ArrayViewReferenceIterator#(t)
    .to_reference_iterator = (.value: &ArrayView#(t)) -> (.iterator: IteratorType) {
        iterator = (._view = value&, ._index = 0)
    }
)

implement#(.t: Type: ImplicitlyCopyable) Iterable#(MutableArrayView#(t)) (
    .Item         : Type = t
    .IteratorType : Type = ArrayViewIterator#(t)
    .to_iterator  = (.value: &MutableArrayView#(t)) -> (.iterator: IteratorType) {
        iterator = (._view = as_readonly(value), ._index = 0)
    }
)

implement#(.t: Type) ReferenceIterable#(MutableArrayView#(t)) (
    .Item                  : Type = t
    .IteratorType          : Type = ArrayViewReferenceIterator#(t)
    .to_reference_iterator = (.value: &MutableArrayView#(t)) -> (.iterator: IteratorType) {
        iterator = (._view = as_readonly(value), ._index = 0)
    }
)

implement#(.t: Type) MutableReferenceIterable#(MutableArrayView#(t)) (
    .Item         : Type = t
    .IteratorType : Type = ArrayViewMutableReferenceIterator#(t)
    .to_mutable_reference_iterator = (.value: $&MutableArrayView#(t)) -> (
        .iterator : IteratorType
    ) {
        iterator = (._view = value&, ._index = 0)
    }
)

ArrayViewIterator := #(.t: Type) (
    ._view  : ArrayView#(.t: t)
    ._index : UIntNative
)

ArrayViewReferenceIterator := #(.t: Type) (
    ._view  : ArrayView#(.t: t)
    ._index : UIntNative
)

ArrayViewMutableReferenceIterator := #(.t: Type) (
    ._view  : MutableArrayView#(.t: t)
    ._index : UIntNative
)

implement#(.t: Type: ImplicitlyCopyable) Iterator#(ArrayViewIterator#(.t: t)) (
    .Item : Type = t

    .has_next = (.self: &ArrayViewIterator#(.t: t)) -> (.ok: Bool) {
        ok = self&._index < length(&self&._view).count
    }

    .next = (.self: $&ArrayViewIterator#(.t: t)) -> (.value: t) {
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

implement#(.t: Type) Iterator#(ArrayViewReferenceIterator#(.t: t)) (
    .Item : Type = &t

    .has_next = (.self: &ArrayViewReferenceIterator#(.t: t)) -> (.ok: Bool) {
        ok = self&._index < length(&self&._view).count
    }

    .next = (.self: $&ArrayViewReferenceIterator#(.t: t)) -> (.value: &t) {
        current_index :: UIntNative = self&._index

        if current_index >= self&._view._length { abort }
        value = trusted_reference_offset#(.t: t)(
            .base = data(&self&._view).pointer, .elements = current_index
        ).reference
        self&._index = current_index + 1
    }
)

implement#(.t: Type) Iterator#(ArrayViewMutableReferenceIterator#(.t: t)) (
    .Item : Type = $&t

    .has_next = (.self: &ArrayViewMutableReferenceIterator#(.t: t)) -> (.ok: Bool) {
        ok = self&._index < length(&self&._view).count
    }

    .next = (.self: $&ArrayViewMutableReferenceIterator#(.t: t)) -> (.value: $&t) {
        current_index :: UIntNative = self&._index

        if current_index >= self&._view._length { abort }
        value = trusted_mutable_reference_offset#(.t: t)(
            .base = data(&self&._view).pointer, .elements = current_index
        ).reference
        self&._index = current_index + 1
    }
)
