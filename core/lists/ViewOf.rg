-- The reference participant preserves mutability in evidence selection.
ViewOf#(.Source: Type): Contract = (
    .Result    : Type
    .make_view : (.array: Source) -> (.result: Result)
)

view#(.Source: Type: ViewOf#(Source)) := (.array: Source) -> (.result: ViewOf#(Source).Result) {
    result = ViewOf#(Source).make_view(.array = array)
}

implement#(.n: UIntNative, .t: Type) ViewOf#($&Array#(.n = n, .t: t)) (
        .Result    : Type = ArrayView#(.t: t)
        .make_view = (
                .array : $&Array#(.n = n, .t: t)
            ) -> (
                .result : Result
            ) {
            result = _fixed_array_view(.array = array)
        }
    )

implement#(.n: UIntNative, .t: Type) ViewOf#(&Array#(.n = n, .t: t)) (
        .Result    : Type = ArrayViewRO#(.t: t)
        .make_view = (
                .array : &Array#(.n = n, .t: t)
            ) -> (
                .result : Result
            ) {
            result = _fixed_array_view_ro(.array = array)
        }
    )

implement#(.t: Type) ViewOf#($&DynamicArray#(.t: t)) (
        .Result    : Type = ArrayView#(.t: t)
        .make_view = (
                .array : $&DynamicArray#(.t: t)
            ) -> (
                .result : Result
            ) {
            result = _dynamic_array_view(.array = array)
        }
    )

implement#(.t: Type) ViewOf#(&DynamicArray#(.t: t)) (
        .Result    : Type = ArrayViewRO#(.t: t)
        .make_view = (
                .array : &DynamicArray#(.t: t)
            ) -> (
                .result : Result
            ) {
            result = _dynamic_array_view_ro(.array = array)
        }
    )
