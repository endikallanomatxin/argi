CleanupCounter := (.value: Int32)

Resource := (.value: Int32, .counter: $&CleanupCounter)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.value = self&.counter&.value + 1
    }
)

make := (.external: $&CleanupCounter) -> (.result: &Resource) {
    resource :: Resource = (.value = 7, .counter = external)
    result = &resource
}

main := () -> (.status_code: Int32 = 0) {
    escaped :: &Resource
    {
        counter ::= CleanupCounter(.value = 0)
        escaped = make(.external = $&counter)
    }
    status_code = escaped&.value
}
