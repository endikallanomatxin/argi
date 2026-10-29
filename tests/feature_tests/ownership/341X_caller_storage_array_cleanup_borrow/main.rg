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
    alive ::= CleanupCounter(.value = 0)
    escaped :: [1]&Resource = (make(.external = $&alive))
    {
        counter ::= CleanupCounter(.value = 0)
        escaped[0] = make(.external = $&counter)
    }
}
