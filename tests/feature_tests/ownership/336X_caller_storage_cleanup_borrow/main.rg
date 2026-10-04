Resource: Type = (.value: Int32)

Resource deinit(.self: $&Resource, .counter: $&Int32 = reach cleanup_counter) -> () := {
    counter&= counter&+ 1
}

make(.external: $&Int32) -> (.result: &Resource) := {
    assume cleanup_counter ::= external
    resource :: Resource = (.value = 7)
    result = &resource
}

main() -> (.status_code: Int32 = 0) := {
    escaped :: &Resource
    {
        counter :: Int32 = 0
        escaped = make(.external = $&counter)
    }
    status_code = escaped&.value
}
