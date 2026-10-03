Token#(.t: Type) : Type = (
    .tag: Int32
)

discard(.value: Int32) -> () := {
    _ ::= value
}

Token init#(.t: Type)(.sample: t) -> (.result: Token#(.t: t)) := {
    #defer discard(.value = 0)
    _ ::= sample
    result = (
        .tag = 1
    )
}

main() -> (.status_code: Int32) := {
    token ::= Token(.sample = 5)
    status_code = token.tag - 1
}
