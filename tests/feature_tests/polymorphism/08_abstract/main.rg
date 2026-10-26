Marker <.Value: Type >: Contract = ()

-- Abstract composed + function requirement
Animal <.Participant: Type >: Contract = (
    .speak : (.who: Participant) -> (.s: &CChar),
    Marker < Participant >
)

Dog := (
    .name : Int32 = 0
)

-- Provide the required function implementation for Dog
_impl_speak_Dog := (.who: Dog) -> (.s: &CChar) {
    s = "Woof"
}

implement Marker < Dog > ()

implement Animal < Dog > (.speak = _impl_speak_Dog)

main := () -> (.status_code: Int32) {
    status_code = 0
}
