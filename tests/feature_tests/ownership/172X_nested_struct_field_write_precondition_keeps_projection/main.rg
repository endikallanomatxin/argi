Thing : Type = (
    .value: Int32
)

Container : Type = (
    .pointer: $&Thing
)

deinit(.self: $&Thing) -> () := {
}

write_nested(.container: $&Container) -> () := {
    container&.pointer&.value = 3
}

main() -> (.status_code: Int32) := {
    x :: Thing = (.value = 1)
    container :: Container = (.pointer = $&x)

    deinit(.self = $&x)
    x = (.value = 2)

    write_nested(.container = $&container)
    status_code = 0
    deinit(.self = $&x)
}
