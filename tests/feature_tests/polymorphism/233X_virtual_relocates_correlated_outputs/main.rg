Mover#(.Participant: Type): Contract = (
    .transfer: (.self: &Participant, .source: $&Resource, .destination: $&Resource, .move: Bool) -> (
        .count  : ?Int32,
        .result : ?Large
    ) where {
        on count ..some { consumes(source) }
        on result ..some { relocates(destination, source) }
        on result ..none {}
    }
)

Manager: Type = (.unused: Int32)

implement Mover#(Manager) (.transfer = _impl_transfer_Manager)

Large: Type = (.values: [128]Int32)

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
        .count  : ?Int32,
        .result : ?Large
    )  {
    count = ..some(.value = 42)
    if move {
        relocate(source, destination)
        result = ..some(.value = Large(zeroed#([128]Int32)()))
        return
    }

    result = ..none
}

main() -> () := {
    manager ::= Manager(0)
    mover ::= to_virtual#(Mover)(&manager)
}
