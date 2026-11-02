Resource := (.value: Int32)

Choice: Type = (..pair(.left: Resource, .right: Resource), ..empty)

implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})

consume := (.target: $&Choice) -> () {
    match target&{
        ..pair $&payload {
            deinit(.self = $&payload&.left)
            if payload&.left.value == 1 { abort }
        }
        ..empty {}
    }
}

main := () -> (.status_code: Int32) {
    value :: Choice = ..pair(.left = (.value = 1), .right = (.value = 2))
    consume(.target = $&value)
    status_code = 42
}
