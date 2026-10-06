Resource: Type = (.counter: $&Int32, .value: Int32)

Resource deinit(.self: $&Resource) -> () := {
    self&.counter&= self&.counter&+ 1
}

make(.counter: $&Int32, .value: Int32) -> (.result: &Resource) := {
    resource :: Resource = (.counter = counter, .value = value)
    result = &resource
}

relay(.counter: $&Int32) -> (.result: &Resource) := {
    temporary ::= make(.counter = counter, .value = 17)
    result = temporary
}

main() -> (.status_code: Int32 = 0) := {
    counter :: Int32 = 0
    {
        reference ::= relay(.counter = $&counter)
        if reference&.value != 17 or counter != 0 {
            status_code = 1
            return
        }
    }
    if counter != 1 { status_code = 2 }
}
