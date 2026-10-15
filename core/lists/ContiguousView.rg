-- View access preserves the reference stored by its nominal representation.
ContiguousView#(.View: Type): Contract = (
    .Pointer  : Type
    .base     : (.self: &View) -> (.pointer: Pointer)
    .subrange : (.self: &View, .start: UIntNative, .count: UIntNative) -> (
        .result : Errable#(View, (..out_of_bounds))
    )
)

data#(
        .View : Type: ContiguousView#(View)
    ) := (
        .self : &View
    ) -> (
        .pointer : ContiguousView#(View).Pointer
    ) {
    pointer = ContiguousView#(View).base(.self = self)
}

slice#(
        .View : Type: ContiguousView#(View)
    ) := (
        .self  : &View,
        .start : UIntNative,
        .count : UIntNative
    ) -> (
        .result : Errable#(View, (..out_of_bounds))
    ) {
    result = ContiguousView#(View).subrange(.self = self, .start = start, .count = count)
}

implement#(.t: Type) ContiguousView#(ArrayView#(.t: t)) (
    .Pointer  : Type              = $&t
    .base     = _array_view_data
    .subrange = _array_view_slice
)

implement#(.t: Type) ContiguousView#(ArrayViewRO#(.t: t)) (
    .Pointer  : Type                 = &t
    .base     = _array_view_ro_data
    .subrange = _array_view_ro_slice
)
