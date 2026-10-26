ArrayIterator := <.n: UIntNative, .t: Type> (
    .array : &Array<.n  = n, .t: t>
    .index : UIntNative
)

ArrayReferenceIterator := <.n: UIntNative, .t: Type> (
    .array : &Array<.n  = n, .t: t>
    .index : UIntNative
)

ArrayMutableReferenceIterator := <.n: UIntNative, .t: Type> (
    .array : $&Array<.n = n, .t: t>
    .index : UIntNative
)

implement<.n: UIntNative, .t: Type> Iterable<Array<.n = n, .t: t>> (
    .Item         : Type = t
    .IteratorType : Type = ArrayIterator<.n = n, .t: t>

    .to_iterator = (.value: &Array<.n = n, .t: t>) -> (.iterator: ArrayIterator<.n = n, .t: t>) {
        iterator = (.array = value, .index = 0)
    }
)

implement<.n: UIntNative, .t: Type> ReferenceIterable<Array<.n = n, .t: t>> (
    .Item         : Type = t
    .IteratorType : Type = ArrayReferenceIterator<.n = n, .t: t>

    .to_reference_iterator = (.value: &Array<.n = n, .t: t>) -> (
        .iterator : ArrayReferenceIterator<.n = n, .t: t>
    ) {
        iterator = (.array = value, .index = 0)
    }
)

implement<.n: UIntNative, .t: Type> MutableReferenceIterable<Array<.n = n, .t: t>> (
    .Item         : Type = t
    .IteratorType : Type = ArrayMutableReferenceIterator<.n = n, .t: t>

    .to_mutable_reference_iterator = (.value: $&Array<.n = n, .t: t>) -> (
        .iterator : ArrayMutableReferenceIterator<.n = n, .t: t>
    ) {
        iterator = (.array = value, .index = 0)
    }
)

implement<.n: UIntNative, .t: Type> Iterator<ArrayIterator<.n = n, .t: t>> (
    .Item : Type = t

    .has_next = (.self: &ArrayIterator<.n = n, .t: t>) -> (.ok: Bool) {
        ok = self&.index < n
    }

    .next = (.self: $&ArrayIterator<.n = n, .t: t>) -> (.value: t) {
        current_index :: UIntNative = self&.index
        value = self&.array&[current_index]
        self&.index = current_index + 1
    }
)

implement<.n: UIntNative, .t: Type> Iterator<ArrayReferenceIterator<.n = n, .t: t>> (
    .Item : Type = &t

    .has_next = (.self: &ArrayReferenceIterator<.n = n, .t: t>) -> (.ok: Bool) {
        ok = self&.index < n
    }

    .next = (.self: $&ArrayReferenceIterator<.n = n, .t: t>) -> (.value: &t) {
        current_index :: UIntNative = self&.index
        value = &self&.array&[current_index]
        self&.index = current_index + 1
    }
)

implement<.n: UIntNative, .t: Type> Iterator<ArrayMutableReferenceIterator<.n = n, .t: t>> (
    .Item : Type = $&t

    .has_next = (.self: &ArrayMutableReferenceIterator<.n = n, .t: t>) -> (.ok: Bool) {
        ok = self&.index < n
    }

    .next = (.self: $&ArrayMutableReferenceIterator<.n = n, .t: t>) -> (.value: $&t) {
        current_index :: UIntNative = self&.index
        value = $&self&.array&[current_index]
        self&.index = current_index + 1
    }
)
