ArrayIterator#(.n: UIntNative, .t: Type): Type = (
    .array : &Array#(.n = n, .t: t)
    .index : UIntNative
)

ArrayROPointerIterator#(.n: UIntNative, .t: Type): Type = (
    .array : &Array#(.n = n, .t: t)
    .index : UIntNative
)

ArrayRWPointerIterator#(.n: UIntNative, .t: Type): Type = (
    .array : $&Array#(.n = n, .t: t)
    .index : UIntNative
)

implement#(
    .n : UIntNative,
    .t : Type
) Iterable#(Array#(.n = n, .t: t)) (
        .Item         : Type = t
        .IteratorType : Type = ArrayIterator#(.n = n, .t: t)

        .to_iterator = (
                .value : &Array#(.n = n, .t: t)
            ) -> (
                .iterator : ArrayIterator#(.n = n, .t: t)
            ) {
            iterator = (
                .array = value
                .index = 0
            )
        }
    )

implement#(
    .n : UIntNative,
    .t : Type
) ROPointerIterable#(Array#(.n = n, .t: t)) (
        .Item         : Type = t
        .IteratorType : Type = ArrayROPointerIterator#(.n = n, .t: t)

        .to_ro_pointer_iterator = (
                .value : &Array#(.n = n, .t: t)
            ) -> (
                .iterator : ArrayROPointerIterator#(.n = n, .t: t)
            ) {
            iterator = (
                .array = value
                .index = 0
            )
        }
    )

implement#(
    .n : UIntNative,
    .t : Type
) RWPointerIterable#(Array#(.n = n, .t: t)) (
        .Item         : Type = t
        .IteratorType : Type = ArrayRWPointerIterator#(.n = n, .t: t)

        .to_rw_pointer_iterator = (
                .value : $&Array#(.n = n, .t: t)
            ) -> (
                .iterator : ArrayRWPointerIterator#(.n = n, .t: t)
            ) {
            iterator = (
                .array = value
                .index = 0
            )
        }
    )

implement#(
    .n : UIntNative,
    .t : Type
) Iterator#(ArrayIterator#(.n = n, .t: t)) (
        .Item : Type = t

        .has_next = (
                .self : &ArrayIterator#(.n = n, .t: t)
            ) -> (
                .ok : Bool
            ) {
            ok = self&.index < n
        }

        .next = (
                .self : $&ArrayIterator#(.n = n, .t: t)
            ) -> (
                .value : t
            ) {
            current_index :: UIntNative = self&.index
            value = self&.array&[current_index]
            self&.index = current_index + 1
        }
    )

implement#(
    .n : UIntNative,
    .t : Type
) Iterator#(ArrayROPointerIterator#(.n = n, .t: t)) (
        .Item : Type = &t

        .has_next = (
                .self : &ArrayROPointerIterator#(.n = n, .t: t)
            ) -> (
                .ok : Bool
            ) {
            ok = self&.index < n
        }

        .next = (
                .self : $&ArrayROPointerIterator#(.n = n, .t: t)
            ) -> (
                .value : &t
            ) {
            current_index :: UIntNative = self&.index
            value = &self&.array&[current_index]
            self&.index = current_index + 1
        }
    )

implement#(
    .n : UIntNative,
    .t : Type
) Iterator#(ArrayRWPointerIterator#(.n = n, .t: t)) (
        .Item : Type = $&t

        .has_next = (
                .self : &ArrayRWPointerIterator#(.n = n, .t: t)
            ) -> (
                .ok : Bool
            ) {
            ok = self&.index < n
        }

        .next = (
                .self : $&ArrayRWPointerIterator#(.n = n, .t: t)
            ) -> (
                .value : $&t
            ) {
            current_index :: UIntNative = self&.index
            value = $&self&.array&[current_index]
            self&.index = current_index + 1
        }
    )
