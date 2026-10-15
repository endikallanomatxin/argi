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
    alive ::= CleanupCounter(.value = 0)
    escaped :: [1]&Resource = (make(.external = $&alive))
    {
        counter ::= CleanupCounter(.value = 0)
        escaped[0] = make(.external = $&counter)
    }
}
