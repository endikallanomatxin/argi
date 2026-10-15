Resource: Type = (.value: &Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {

    }
)

global :: Int32 = 42

release_if(.resource: $&Resource, .replacement: &Int32, .consume: Bool) -> (.result: ?Int32) := {
    if consume {
        deinit(resource)
        result = ..some(.value = 42)
        return
    }

    resource&.value = replacement
    result = ..none
}

make() -> (.result: Resource) := {
    resource ::= Resource(&global)
    local :: Int32 = 43
    selected ::= release_if($&resource, &local, false)

    match selected {
        ..none { result = ~resource }
        ..some _ { result = Resource(&global) }
    }
}

main() -> () := {
    result ::= make()
}
