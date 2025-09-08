-- Abstract composed + function requirement
Animal : Abstract = (
    speak(.self: Any) -> (.s: &Char),
    Addable
)

Dog : Type = (
    .name: Int32 = 0
)

-- Provide the required function implementation for Dog
speak (.self: Dog) -> (.s: &Char) := {
    s = "Woof"
}

Animal canbe Dog
Animal defaultsto Dog

main () -> (.status_code: Int32) := {
    status_code = 0
}

