drops :: Int32 = 0
tokens :: Int32 = 0

Resource := (.value: Int32)

Token := (.value: Int32)

implement Deinit<Resource> (.deinit = (.self: $&Resource) -> () { drops = drops + 1 })

implement Deinit<Token> (.deinit = (.self: $&Token) -> () { tokens = tokens + 1 })

select_target := (.token: Token, .target: $&Resource) -> (.result: $&Resource) {
    owner ::= ~token
    result = target
}

replace := (.target: $&Resource, .token: Token, .branch: Bool) -> () {
    previous ::= target
    if branch {
        deinit(.self = target)
        target&= Resource(.value = 3)
    } else {
        deinit(.self = target)
        target&= Resource(.value = 4)
    }
    [select_target(.token = ~token, .target = target)]&= Resource(.value = 9)
    if previous&.value == 9 { abort }
}

main := () -> (.status_code: Int32) {
    {
        owner :: Resource = Resource(.value = 1)
        token :: Token = Token(.value = 0)
        replace(.target = $&owner, .token = ~token, .branch = true)
        if owner.value != 9 { abort }
        if drops != 2 or tokens != 1 { abort }
    }
    if drops != 3 or tokens != 1 { abort }
    status_code = 42
}
