Resource: Type = (.counter: $&Int32, .value: Int32)

Resource deinit(.self: $&Resource) -> () := {
    self&.counter&= self&.counter&+ 1
}

make(.counter: $&Int32, .value: Int32) -> (.result: &Resource) := {
    resource :: Resource = (.counter = counter, .value = value)
    result = &resource
}

main() -> (.status_code: Int32 = 0) := {
    counter :: Int32 = 0
    {
        first ::= make(.counter = $&counter, .value = 7)
        second ::= make(.counter = $&counter, .value = 11)
        if first&.value != 7 or second&.value != 11 or counter != 0 {
            status_code = 1
            return
        }
    }
    if counter != 2 { status_code = 2 }
}
