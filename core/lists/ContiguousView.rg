-- View access preserves the reference stored by its nominal representation.
ContiguousView#(.View: Type): Contract = (
    .Reference : Type
    .base      : (.self: &View) -> (.pointer: Reference)
    .subrange  : (.self: &View, .start: UIntNative, .count: UIntNative) -> (
        .result : Errable#(View, (..out_of_bounds))
    )
)

data#(.View: Type: ContiguousView#(View)) := (.self: &View) -> (
    .pointer : ContiguousView#(View).Reference
) {
    pointer = ContiguousView#(View).base(.self = self)
}

slice#(.View: Type: ContiguousView#(View)) := (
    .self: &View, .start: UIntNative, .count: UIntNative
) -> (.result: Errable#(View, (..out_of_bounds))) {
    result = ContiguousView#(View).subrange(.self = self, .start = start, .count = count)
}

implement#(.t: Type) ContiguousView#(MutableArrayView#(.t: t)) (
    .Reference : Type = $&t
    .base      = _mutable_array_view_data
    .subrange  = _mutable_array_view_slice
)

implement#(.t: Type) ContiguousView#(ArrayView#(.t: t)) (
    .Reference : Type = &t
    .base      = _array_view_data
    .subrange  = _array_view_slice
)
