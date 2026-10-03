Token#(.t: Type) : Type = (
    .tag: Int32
)

Token init#(.t: Type)(.sample: t) -> (.result: Token#(.t: t)) := {
    _ ::= sample
    result = (
        .tag = 1
    )
}

main () -> (.status_code: Int32) := {
    int_token ::= Token(.sample = 5)
    char_token ::= Token(.sample = 'a')

    if int_token.tag != 1 {
        status_code = 1
        return
    }

    if char_token.tag != 1 {
        status_code = 2
        return
    }

    status_code = 0
}
