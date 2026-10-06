Resource: Type = (.value: Int32)

drops :: Int32 = 0

Resource deinit(.self: $&Resource) -> () := { drops = drops + 1 }

choose(.left: Bool) -> (.result: &Resource) := {
    if left {
        first :: Resource = (.value = 3)
        result = &first
    } else {
        second :: Resource = (.value = 5)
        result = &second
    }
}

main() -> (.status_code: Int32 = 0) := {
    {
        left ::= choose(.left = true)
        right ::= choose(.left = false)
        if left&.value != 3 or right&.value != 5 or drops != 0 { status_code = 1 }
    }
    if drops != 2 { status_code = 2 }
}
