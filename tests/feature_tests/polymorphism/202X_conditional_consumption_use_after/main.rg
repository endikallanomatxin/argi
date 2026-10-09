Resource: Type = (.value: Int32)

Resource deinit(.self: $&Resource) -> () := {}

release_if(.resource: $&Resource, .consume: Bool) -> (.result: ?Int32) := {
    if consume {
        deinit(resource)
        result = ..some(.value = 42)
        return
    }

    result = ..none
}

main() -> (.status_code: Int32 = 0) := {
    resource ::= Resource(42)
    result ::= release_if($&resource, true)

    match result {
        ..some _ { if resource.value != 42 { status_code = 1 } }
        ..none {}
    }
}
