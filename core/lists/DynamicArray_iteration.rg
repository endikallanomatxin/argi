implement#(.t: Type: ImplicitlyCopyable) Iterable#(DynamicArray#(.t: t)) (
    .Item         : Type = t
    .IteratorType : Type = ArrayViewIterator#(.t: t)

    .to_iterator = (.value: &DynamicArray#(.t: t)) -> (.iterator: ArrayViewIterator#(.t: t)) {
        iterator = (._view = view(.self = value), ._index = 0)
    }
)

implement#(.t: Type) ReferenceIterable#(DynamicArray#(.t: t)) (
    .Item         : Type = t
    .IteratorType : Type = ArrayViewReferenceIterator#(.t: t)

    .to_reference_iterator = (.value: &DynamicArray#(.t: t)) -> (
        .iterator : ArrayViewReferenceIterator#(.t: t)
    ) {
        iterator = (._view = view(.self = value), ._index = 0)
    }
)

implement#(.t: Type) MutableReferenceIterable#(DynamicArray#(.t: t)) (
    .Item         : Type = t
    .IteratorType : Type = ArrayViewMutableReferenceIterator#(.t: t)

    .to_mutable_reference_iterator = (.value: $&DynamicArray#(.t: t)) -> (
        .iterator : ArrayViewMutableReferenceIterator#(.t: t)
    ) {
        iterator = (._view = view(.self = value), ._index = 0)
    }
)
