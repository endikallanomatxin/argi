Mover#(.Participant: Type): Contract = (
    .transfer: (.self: &Participant, .source: $&Resource, .destination: $&Resource, .move: Bool) -> (
        .result : ?Int32
    ) where {
        relocates(destination, source)
        on result ..some { relocates(destination, source) }
        on result ..none {}
    }
)

Manager: Type = (.unused: Int32)

implement Mover#(Manager) (.transfer = _impl_transfer_Manager)

Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

_impl_transfer_Manager := (
        .self        : &Manager,
        .source      : $&Resource,
        .destination : $&Resource,
        .move        : Bool
    ) -> (
        .result : ?Int32
    )  {
    if move {
        relocate(source, destination)
        result = ..some(.value = 1)
        return
    }

    result = ..none
}

transfer_owned(
        .mover       : &Virtual#(Mover),
        .source      : $&Resource,
        .destination : $&Resource,
        .move        : Bool
    ) -> (
        .result : ?Int32
    ) := {
    result = transfer(mover, source, destination, move)
}

main() -> () := {
    manager ::= Manager(0)
    mover ::= to_virtual#(Mover)(&manager)
}
