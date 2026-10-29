Fixed#(.Participant: Type): Contract = (
    .n    : Int
    .item : Type

    .read : (.self: &Participant) -> (.value: item) where {}
)

Integer := (.value: Int32)

Floating := (.value: Float64)

implement Fixed#(Integer) (.n: Int = 1, .item: Type = Int32, .read = _impl_read_Integer)

implement Fixed#(Floating) (.n: Int = 2, .item: Type = Float64, .read = _impl_read_Floating)

_impl_read_Integer := (.self: &Integer) -> (.value: Int32) { value = self&.value }

_impl_read_Floating := (.self: &Floating) -> (.value: Float64) { value = self&.value }

consume_integer := (.input: &Virtual#(Fixed#(.n = 1, .item: Int32))) -> (
    .value : Int32
) {
    value = read(.self = input)
}

consume_float := (.input: &Virtual#(Fixed#(.n = 2, .item: Float64))) -> (
    .value : Float64
) {
    value = read(.self = input)
}

wrap := #(.t: Type: Fixed#(.n = 1, .item: Int32)) (.value: &t) -> (
    .result : Virtual#(Fixed#(.n = 1, .item: Int32))
) {
    result = to_virtual#(.contract: Fixed#(.n = 1, .item: Int32))(.value = value)
}

main := () -> (.status_code: Int32 = 0) {
    integer :: Integer = (.value = 17)
    floating :: Floating = (.value = 2.5)
    left ::= wrap(.value = &integer).result
    right :: Virtual#(Fixed#(.n = 2, .item: Float64)) = to_virtual(
        .value = &floating
    )
    if consume_integer(.input = &left).value != 17 { abort }
    if consume_float(.input = &right).value != 2.5 { abort }
}
