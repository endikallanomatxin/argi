CleanupCounter: Type = (.value: Int32)
Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource, .counter: $&CleanupCounter = reach cleanup_counter) -> () {
        counter&.value = counter&.value + 1
    }
)

make(.external: $&CleanupCounter) -> (.result: &Resource) := {
    assume cleanup_counter ::= external
    resource :: Resource = (.value = 7)
    result = &resource
}

main() -> (.status_code: Int32 = 0) := {
    counter ::= CleanupCounter(.value = 0)
    {
        references :: [1]&Resource = (make(.external = $&counter))
        references[0] = make(.external = $&counter)
        if counter.value != 0 { status_code = 1 }
    }
    if counter.value != 2 { status_code = 2 }
}
