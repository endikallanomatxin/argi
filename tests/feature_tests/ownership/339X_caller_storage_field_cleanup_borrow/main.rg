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

Holder := (.reference: &Resource)

main := () -> (.status_code: Int32 = 0) {
    escaped :: Holder
    {
        counter ::= CleanupCounter(.value = 0)
        escaped.reference = make(.external = $&counter)
    }
}
