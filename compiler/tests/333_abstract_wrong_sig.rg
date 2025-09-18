Dog : Type = (
    .name: Int32 = 0
)

Animal : Abstract = (
    speak(.who: Self) -> (.s: &Char)
)

Animal canbe Dog
Animal defaultsto Dog

-- Wrong function signature: expects a &Char return type, but it's an Int32
speak (.who: Dog) -> (.s: Int32) := {
    s = 42
}

main () -> (.status_code: Int32) := {
    status_code = 0
}

