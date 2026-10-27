-- The reference participant preserves mutability in evidence selection.
Viewable#(.Source: Type): Contract = (
    .Result    : Type
    .make_view : (.self: Source) -> (.view: Result)
)

view := #(.Source: Type: Viewable#(Source)) (.self: Source) -> (.view: Viewable#(Source).Result) {
    view = Viewable#(Source).make_view(.self = self)
}

implement#(.n: UIntNative, .t: Type) Viewable#($&Array#(.n = n, .t: t)) (
    .Result    : Type = MutableArrayView#(.t: t)
    .make_view = (.self: $&Array#(.n = n, .t: t)) -> (.view: Result) {
        view = _fixed_mutable_array_view(.array = self)
    }
)

implement#(.n: UIntNative, .t: Type) Viewable#(&Array#(.n = n, .t: t)) (
    .Result    : Type = ArrayView#(.t: t)
    .make_view = (.self: &Array#(.n = n, .t: t)) -> (.view: Result) {
        view = _fixed_array_view(.array = self)
    }
)

implement#(.t: Type) Viewable#($&DynamicArray#(.t: t)) (
    .Result    : Type = MutableArrayView#(.t: t)
    .make_view = (.self: $&DynamicArray#(.t: t)) -> (.view: Result) {
        view = _dynamic_array_mutable_view(.array = self)
    }
)

implement#(.t: Type) Viewable#(&DynamicArray#(.t: t)) (
    .Result    : Type = ArrayView#(.t: t)
    .make_view = (.self: &DynamicArray#(.t: t)) -> (.view: Result) {
        view = _dynamic_array_view(.array = self)
    }
)
