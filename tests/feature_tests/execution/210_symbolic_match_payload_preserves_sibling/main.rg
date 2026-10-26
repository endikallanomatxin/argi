drops :: Int32 = 0

Resource := (.value: Int32)

Choice: Type = (..pair(.left: Resource, .right: Resource), ..empty)

implement Deinit<Resource> (.deinit = (.self: $&Resource) -> () { drops = drops + 1 })

consume := (.target: $&Choice) -> (.result: Int32) {
    match target&{
        ..pair $&payload {
            deinit(.self = $&payload&.left)
            result = payload&.right.value
        }
        ..empty { result = 0 }
    }
}

main := () -> (.status_code: Int32) {
    {
        value :: Choice = ..pair(.left = (.value = 1), .right = (.value = 42))
        if consume(.target = $&value) != 42 { abort }
    }
    if drops != 2 { abort }
    status_code = 42
}
