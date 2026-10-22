tokens :: Int32 = 0

Token: Type = (.value: Int32)

implement Deinit#(Token) (.deinit = (.self: $&Token) -> () { tokens = tokens + 1 })

drops :: Int32 = 0

Resource: Type = (.value: Int32)

Choice: Type = (..pair(.left: Resource, .right: Resource), ..empty)

implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () { drops = drops + 1 })

select_choice(.target: $&Choice, .token: Token) -> (.result: $&Choice) := {
    held ::= ~token
    result = target
}

consume(.target: $&Choice, .token: Token) -> (.result: Int32) := {
    match [select_choice(.target = target, .token = ~token)]&{
        ..pair $&payload {
            deinit(.self = $&payload&.left)
            result = payload&.right.value
        }
        ..empty { result = 0 }
    }
}

main() -> (.status_code: Int32) := {
    {
        value :: Choice = ..pair(.left = (.value = 1), .right = (.value = 42))
        token :: Token = (.value = 0)
        if consume(.target = $&value, .token = ~token) != 42 { abort }
    }
    if drops != 2 or tokens != 1 { abort }
    status_code = 42
}
