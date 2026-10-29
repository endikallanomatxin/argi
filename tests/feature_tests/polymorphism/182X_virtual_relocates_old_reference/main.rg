Mover#(.Participant: Type): Contract = (
    .transfer : (.self: &Participant, .source: $&Resource, .destination: $&Resource) -> ()
    where relocates(destination, source)
)

Manager := (.unused: Int32)

implement Mover#(Manager) (.transfer = _impl_transfer_Manager)

Resource := (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

_impl_transfer_Manager := (.self: &Manager, .source: $&Resource, .destination: $&Resource) -> () {
    relocate(source, destination)
}

transfer_owned := (.mover: &Virtual#(Mover), .source: $&Resource, .destination: $&Resource) -> (
) {
    transfer(mover, source, destination)
}

main := () -> (.status_code: Int32 = 0) {
    manager ::= Manager(0)
    mover ::= to_virtual#(Mover)(&manager)

    if true {
        source ::= Resource(42)
        destination ::= Resource(0)
        deinit($&destination)
        previous ::= &source.value
        transfer_owned(&mover, $&source, $&destination)
        if previous&!= 42 { status_code = 2 }
    }
    if drops != 2 { status_code = 1 }
}
