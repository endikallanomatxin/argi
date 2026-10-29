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
    counter ::= CleanupCounter(.value = 0)
    {
        references :: [1]&Resource = (make(.external = $&counter))
        references[0] = make(.external = $&counter)
        if counter.value != 0 { status_code = 1 }
    }
    if counter.value != 2 { status_code = 2 }
}
