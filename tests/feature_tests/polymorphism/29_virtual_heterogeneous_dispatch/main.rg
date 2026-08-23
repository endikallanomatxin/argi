Valued : Abstract = (
    get_value(.self: &Self) -> (.value: Int32)
)

First : Type = (
    .value: Int32
)

Second : Type = (
    .value: Int32
)

First implements Valued
Second implements Valued

get_value(.self: &First) -> (.value: Int32) := {
    value = self&.value
}

get_value(.self: &Second) -> (.value: Int32) := {
    value = self&.value * 2
}

main() -> (.status_code: Int32) := {
    first :: First = (.value = 10)
    second :: Second = (.value = 16)
    values :: Array#(.n = 2, .t: Virtual#(.abstract: Valued)) = (
        to_virtual#(.abstract: Valued)(.value = $&first),
        to_virtual#(.abstract: Valued)(.value = $&second),
    )

    a ::= get_value(.self = &values[0])
    b ::= get_value(.self = &values[1])
    status_code = a + b - 42
}
