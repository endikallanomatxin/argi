Thing : Type = (
    .value: Int32
)

deinit(.self: $&Thing) -> () := {
}

main() -> (.status_code: Int32) := {
    x :: Thing = (.value = 1)
    stale ::= $&x

    deinit(.self = $&x)
    x = (.value = 2)

    stale&.value = 3
    status_code = 0
    deinit(.self = $&x)
}
