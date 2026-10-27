Dog := (
    .name : Int32 = 0
)

Animal#(.Participant: Type): Contract = (
    .speak : (.who: Participant) -> (.s: &CChar)
)

implement Animal#(Dog) ()

main := () -> (.status_code: Int32) {
    status_code = 0
}
