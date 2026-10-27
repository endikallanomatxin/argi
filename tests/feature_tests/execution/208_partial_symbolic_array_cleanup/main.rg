Counter := (.drops: Int32 = 0)

tokens :: Int32 = 0

Resource := (.value: Int32, .counter: $&Counter)

Token := (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { self&.counter&.drops = [self&.counter&.drops + 1] }
)

implement Deinit#(Token) (.deinit = (.self: $&Token) -> () { tokens = tokens + 1 })

select_array := (.target: $&[2]Resource, .token: Token) -> (.result: $&[2]Resource) {
    held ::= ~token
    result = target
}

replace := (.target: $&[2]Resource, .token: Token, .counter: $&Counter) -> () {
    deinit(.self = $&target&[0])
    [select_array(.target = target, .token = ~token)]&= (
        (.value = 3, .counter = counter),
        (.value = 4, .counter = counter)
    )
}

main := () -> (.status_code: Int32) {
    counter :: Counter = Counter()
    {
        values :: [2]Resource = (
            (.value = 1, .counter = $&counter),
            (.value = 2, .counter = $&counter)
        )
        token :: Token = (.value = 0)
        replace(.target = $&values, .token = ~token, .counter = $&counter)
        if values[0].value != 3 or values[1].value != 4 { abort }
    }
    if counter.drops != 4 or tokens != 1 { abort }
    status_code = 42
}
