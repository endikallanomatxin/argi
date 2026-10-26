Releaser<.Participant: Type>: Contract = (
    .release : (.self: $&Participant) -> () where consumes(self)
)

Manager := (.unused: Int32)

implement Releaser<Manager> (.release = _impl_release_Manager)

implement Deinit<Manager> (
    .deinit = (.self: $&Manager) -> () {

    }
)

_impl_release_Manager := (.self: $&Manager) -> () { deinit(self) }

main := () -> () {
    manager ::= Manager(0)
    releaser ::= to_virtual<Releaser>($&manager)
}
