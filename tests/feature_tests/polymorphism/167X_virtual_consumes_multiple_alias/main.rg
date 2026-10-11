Releaser: Abstract = (
    release(.self: &Self, .first: $&Resource, .second: $&Resource) -> () where consumes(
        first
        second
    )
)

Manager: Type = (.unused: Int32)

Manager implements Releaser

Resource: Type = (.value: Int32)

Resource deinit(.self: $&Resource) -> () := { drops = drops + 1 }

drops :: Int32 = 0

release(.self: &Manager, .first: $&Resource, .second: $&Resource) -> () := {
    deinit(first)
    deinit(second)
}

release_owned(.releaser: &Virtual#(Releaser), .first: $&Resource, .second: $&Resource) -> () := {
    release(releaser, first, second)
}

main() -> (.status_code: Int32 = 0) := {
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)(&manager)

    if true {
        first ::= Resource(42)
        second ::= Resource(43)
        release_owned(&releaser, $&first, $&first)
    }
    if drops != 2 { status_code = 1 }
}
