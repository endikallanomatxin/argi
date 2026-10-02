Thing : Type = (
    .value: Int32
)

write(.p: $&Thing) -> () := {
    p&.value = 3
}

main() -> (.status_code: Int32) := {
    x :: Thing = (.value = 1)
    write(.p = $&x)

    if x.value == 3 {
        status_code = 0
    } else {
        status_code = 1
    }
}
