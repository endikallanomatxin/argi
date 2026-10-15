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

Holder: Type = (.reference: &Resource)
main() -> (.status_code: Int32 = 0) := {
    escaped :: Holder
    {
        counter ::= CleanupCounter(.value = 0)
        escaped.reference = make(.external = $&counter)
    }
}
