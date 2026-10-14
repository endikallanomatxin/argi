Mover#(.Participant: Type): Contract = (
    .transfer: (.self: &Participant, .source: $&Resource, .destination: $&Resource, .move: Bool) -> (
        .count  : Int32,
        .result : ?Large
    ) where {
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
        .count  : Int32,
        .result : ?Large
    )  {
    count = 42
    if move {
        relocate(source, destination)
        result = ..some(.value = Large(zeroed#([128]Int32)()))
        return
    }

    result = ..none
}

main() -> (.status_code: Int32 = 0) := {
    manager ::= Manager(0)
    mover ::= to_virtual#(Mover)(&manager)

    if true {
        source ::= Resource(42)
        destination ::= Resource(0)
        deinit($&destination)
        outcome ::= transfer(&mover, $&source, $&destination, true)

        match outcome.result {
            ..some _ { if destination.value != 42 { status_code = 2 } }
            ..none { status_code = 3 }
        }
    }
    if drops != 2 { status_code = 1 }

    if true {
        source ::= Resource(43)
        destination ::= Resource(0)
        deinit($&destination)
        previous ::= &source
        outcome ::= transfer(&mover, $&source, $&destination, false)

        match outcome.result {
            ..some _ { status_code = 4 }
            ..none { if previous&.value != 43 or source.value != 43 { status_code = 5 } }
        }
    }
    if drops != 4 { status_code = 6 }

    if true {
        source ::= Resource(44)
        destination ::= Resource(0)
        deinit($&destination)
        transfer(&mover, $&source, $&destination, true)
    }
    if drops != 6 { status_code = 7 }

    if true {
        source ::= Resource(45)
        destination ::= Resource(0)
        deinit($&destination)
        transfer(&mover, $&source, $&destination, false)
    }
    if drops != 8 { status_code = 8 }
}
