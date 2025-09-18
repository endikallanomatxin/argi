Dog : Type = (
    .name: Int32 = 0
)

Animal : Abstract = (
    speak(.who: Self) -> (.s: &Char)
)

Animal canbe Dog
Animal defaultsto Dog

main () -> (.status_code: Int32) := {
    status_code = 0
}

