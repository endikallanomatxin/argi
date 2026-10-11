Resource: Type = (.value: Int32)

Resource deinit(.self: $&Resource) -> () := {}

release_if(.resource: $&Resource, .consume: Bool) -> () := {
    if consume { deinit(resource) }
}

main() -> () := {
    resource ::= Resource(42)
    release_if($&resource, true)
}
