Dog := (
    .name : Int32 = 0
)

Animal<.Participant: Type>: Contract = (
    .speak : (.who: Participant) -> (.s: &CChar)
)

implement Animal<Dog> (.speak = _impl_speak_Dog)

-- Wrong function signature: expects a &CChar return type, but it's an Int32
_impl_speak_Dog := (.who: Dog) -> (.s: Int32) {
    s = 42
}

main := () -> (.status_code: Int32) {
    status_code = 0
}
