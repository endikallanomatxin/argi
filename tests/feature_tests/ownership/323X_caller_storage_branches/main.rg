Resource: Type = (.counter: $&Int32, .value: Int32)

Resource deinit(.self: $&Resource) -> () := {
    self&.counter&= self&.counter&+ 1
}

make(.counter: $&Int32, .value: Int32) -> (.result: &Resource) := {
    resource :: Resource = (.counter = counter, .value = value)
    result = &resource
}

choose(.counter: $&Int32, .left: Bool) -> (.result: &Resource) := {
    first :: Resource = (.counter = counter, .value = 3)
    second :: Resource = (.counter = counter, .value = 5)
    if left { result = &first } else { result = &second }
}

main() -> (.status_code: Int32 = 0) := {
    counter :: Int32 = 0
    {
        left ::= choose(.counter = $&counter, .left = true)
        right ::= choose(.counter = $&counter, .left = false)
        if left&.value != 3 or right&.value != 5 or counter != 0 {
            status_code = 1
            return
        }
    }
    if counter != 4 { status_code = 2 }
}
