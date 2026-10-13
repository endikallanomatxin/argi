Mover: Abstract = (
    transfer(
        .self        : &Self,
        .source      : $&Resource,
        .destination : $&Resource,
        .alternative : $&Resource,
        .move        : Bool
    ) -> (.result: ?Int32) where {
        on result ..some { relocates(destination, source) }
        on result ..none { relocates(alternative, source) }
    }
)

Manager: Type = (.unused: Int32)

Manager implements Mover

Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

transfer(
        .self        : &Manager,
        .source      : $&Resource,
        .destination : $&Resource,
        .alternative : $&Resource,
        .move        : Bool
    ) -> (
        .result : ?Int32
    ) := {
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
        .alternative : $&Resource,
        .move        : Bool
    ) -> (
        .result : ?Int32
    ) := {
    result = transfer(mover, source, destination, alternative, move)
}

main() -> () := {
    manager ::= Manager(0)
    mover ::= to_virtual#(Mover)(&manager)
}
