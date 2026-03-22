Animal : Abstract = (
    clone(.who: Self) -> (.copy: Self)
)

Dog : Type = (
    .value: Int32 = 0
)

clone(.who: Dog) -> (.copy: Dog) := {
    copy = who
}

Dog implements Animal
Animal defaultsto Dog

main () -> (.status_code: Int32) := {
    status_code = 0
}
