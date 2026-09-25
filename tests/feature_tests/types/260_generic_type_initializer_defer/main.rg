Token#(.t: Type) : Type = (
    .tag: Int32
)

discard(.value: Int32) -> () := {
    _ ::= value
}

init#(.t: Type)(.p: $&Token#(.t: t), .sample: t) -> () := {
    #defer discard(.value = 0)
    _ ::= sample
    p& = (
        .tag = 1
    )
}

main() -> (.status_code: Int32) := {
    token ::= Token(.sample = 5)
    status_code = token.tag - 1
}
