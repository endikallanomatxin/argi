Animal#(.Participant: Type): Contract = (
    .clone : (.who: Participant) -> (.copy: Participant)
)

Dog := (
    .value : Int32 = 0
)

implement ImplicitlyCopyable#(Dog) ()

_impl_clone_Dog := (.who: Dog) -> (.copy: Dog) {
    copy = who
}

implement Animal#(Dog) (.clone = _impl_clone_Dog)

main := () -> (.status_code: Int32) {
    status_code = 0
}
