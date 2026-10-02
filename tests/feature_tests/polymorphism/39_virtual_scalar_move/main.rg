Echo : Abstract = (
    echo(.self: &Self, .input: Int32) -> (.output: Int32)
)

Direct : Type = (.marker: Int32)
Moved : Type = (.marker: Int32)
Direct implements Echo
Moved implements Echo

echo(.self: &Direct, .input: Int32) -> (.output: Int32) := {
    output = input
}

echo(.self: &Moved, .input: Int32) -> (.output: Int32) := {
    output = ~input
}

register_moved(.value: $&Moved) -> () := {
    unused ::= to_virtual#(.abstract: Echo)(.value = value)
}

main() -> (.status_code: Int32 = 0) := {
    moved :: Moved = (.marker = 0)
    register_moved(.value = $&moved)
    direct :: Direct = (.marker = 0)
    virtual ::= to_virtual#(.abstract: Echo)(.value = $&direct)
    echoed ::= echo(.self = &virtual, .input = 7)
    if echoed != 7 { status_code = 1 }
}
