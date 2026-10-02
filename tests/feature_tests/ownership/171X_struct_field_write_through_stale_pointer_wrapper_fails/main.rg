Thing : Type = (
    .value: Int32
)

deinit(.self: $&Thing) -> () := {
}

write(.p: $&Thing) -> () := {
    p&.value = 3
}

main() -> (.status_code: Int32) := {
    x :: Thing = (.value = 1)
    stale ::= $&x

    deinit(.self = $&x)
    x = (.value = 2)

    write(.p = stale)
    status_code = 0
    deinit(.self = $&x)
}
