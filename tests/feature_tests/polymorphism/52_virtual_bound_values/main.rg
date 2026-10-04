Fixed#(.n: UIntNative, .item: Type): Abstract = (
    read(.self: &Self) -> (.value: item)
)

Integer: Type = (.value: Int32)

Floating: Type = (.value: Float64)

Integer implements Fixed#(.n = 1, .item: Int32)
Floating implements Fixed#(.n = 2, .item: Float64)

read(.self: &Integer) -> (.value: Int32) := { value = self&.value }

read(.self: &Floating) -> (.value: Float64) := { value = self&.value }

consume_integer(.input: &Virtual#(.abstract: Fixed#(.n = 1, .item: Int32))) -> (.value: Int32) := {
    value = read(.self = input)
}

consume_float(.input: &Virtual#(.abstract: Fixed#(.n = 2, .item: Float64))) -> (.value: Float64) := {
    value = read(.self = input)
}

wrap#(
        .t : Type: Fixed#(.n = 1, .item: Int32)
    )(
        .value : &t
    ) -> (
        .result : Virtual#(.abstract: Fixed#(.n = 1, .item: Int32))
    ) := {
    result = to_virtual#(.abstract: Fixed#(.n = 1, .item: Int32))(.value = value)
}

main() -> (.status_code: Int32 = 0) := {
    integer :: Integer = (.value = 17)
    floating :: Floating = (.value = 2.5)
    left ::= wrap(.value = &integer).result
    right :: Virtual#(.abstract: Fixed#(.n = 2, .item: Float64)) = to_virtual(.value = &floating)
    if consume_integer(.input = &left).value != 17 { abort }
    if consume_float(.input = &right).value != 2.5 { abort }
}
