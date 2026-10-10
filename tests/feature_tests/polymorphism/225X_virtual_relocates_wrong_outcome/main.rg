Mover: Abstract = (
    transfer(.self: &Self, .source: $&Resource, .destination: $&Resource, .move: Bool) -> (
        .result : ?Int32
    ) where {
        on result ..some { relocates(destination, source) }
        on result ..none {}
    }
)

Manager: Type = (.unused: Int32)

Manager implements Mover

Resource: Type = (.value: Int32)

Resource deinit(.self: $&Resource) -> () := { drops = drops + 1 }

drops :: Int32 = 0

transfer(
        .self        : &Manager,
        .source      : $&Resource,
        .destination : $&Resource,
        .move        : Bool
    ) -> (
        .result : ?Int32
    ) := {
    if move == false {
        relocate(source, destination)
        result = ..none
        return
    }

    result = ..some(.value = 1)
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
