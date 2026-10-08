Large: Type = (.values: [128]Int32)

Releaser: Abstract = (
    release(.self: &Self, .resource: $&Resource) -> (.result: Large) where consumes(resource)
)

Manager: Type = (.unused: Int32)

Manager implements Releaser

Resource: Type = (.value: Int32)

Resource deinit(.self: $&Resource) -> () := { drops = drops + 1 }

drops :: Int32 = 0

release(.self: &Manager, .resource: $&Resource) -> (.result: Large) := {
    deinit(resource)
    result = Large(zeroed#([128]Int32)())
}

main() -> (.status_code: Int32 = 0) := {
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)(&manager)

    if true {
        resource ::= Resource(42)
        large ::= release(&releaser, $&resource)
        if large.values[127] != 0 { status_code = 2 }
    }
    if drops != 1 { status_code = 1 }
}
