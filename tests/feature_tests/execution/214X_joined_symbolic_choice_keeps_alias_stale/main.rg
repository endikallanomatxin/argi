drops :: Int32 = 0
tokens :: Int32 = 0
whole_drops :: Int32 = 0

Resource := (.value: Int32)

Token := (.value: Int32)

Choice: Type = (..pair(.left: Resource, .right: Resource), ..empty)

implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () { drops = drops + 1 })

implement Deinit#(Token) (.deinit = (.self: $&Token) -> () { tokens = tokens + 1 })

implement Deinit#(Choice) (
    .deinit = (.self: $&Choice) -> () {
        whole_drops = whole_drops + 1
        match self&{
            ..pair $&payload {
                deinit(.self = $&payload&.left)
                deinit(.self = $&payload&.right)
            }
            ..empty {}
        }
    }
)

select_choice := (.target: $&Choice, .token: Token) -> (.result: $&Choice) {
    held ::= ~token
    result = target
}

replace := (.target: $&Choice, .token: Token, .consume: Bool) -> () {
    previous ::= target
    match target&{
        ..pair $&payload { if consume { deinit(.self = $&payload&.left) } }
        ..empty {}
    }
    [select_choice(.target = target, .token = ~token)]&= ..pair(
        .left  = (.value = 3)
        .right = (.value = 4)
    )
    match previous&{
        ..pair $&payload { if payload&.right.value != 4 { abort } }
        ..empty {}
    }
}

main := () -> (.status_code: Int32) {
    {
        value :: Choice = ..pair(.left = (.value = 1), .right = (.value = 2))
        token :: Token = (.value = 0)
        replace(.target = $&value, .token = ~token, .consume = true)
    }
    if drops != 4 or tokens != 1 or whole_drops != 1 { abort }
    {
        value :: Choice = ..pair(.left = (.value = 1), .right = (.value = 2))
        token :: Token = (.value = 0)
        replace(.target = $&value, .token = ~token, .consume = false)
    }
    if drops != 8 or tokens != 2 or whole_drops != 3 { abort }
    {
        value :: Choice = ..empty
        token :: Token = (.value = 0)
        replace(.target = $&value, .token = ~token, .consume = false)
    }
    if drops != 10 or tokens != 3 or whole_drops != 5 { abort }
    status_code = 42
}
