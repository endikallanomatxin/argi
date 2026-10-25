tokens :: Int32 = 0

Token: Type = (.value: Int32)

implement Deinit#(Token) (.deinit = (.self: $&Token) -> () { tokens = tokens + 1 })

Counter: Type = (.count: Int32 = 0)

Resource: Type = (.counter: $&Counter)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { self&.counter&.count = self&.counter&.count + 1 }
)

Wrapper: Type = (.item: Resource, .sibling: Resource, .whole: $&Counter)

implement Deinit#(Wrapper) (
    .deinit = (.self: $&Wrapper) -> () {
        self&.whole&.count = self&.whole&.count + 1
        deinit(.self = $&self&.item)
        deinit(.self = $&self&.sibling)
    }
)

select_owner(.owner: $&Wrapper, .token: Token) -> (.result: $&Wrapper) := {
    held ::= ~token
    result = owner
}

replace_incomplete(.owner: $&Wrapper, .counter: $&Counter, .whole: $&Counter) -> () := {
    deinit(.self = $&owner&.item)
    token :: Token = Token(.value = 0)
    [select_owner(.owner = owner, .token = ~token)]&= Wrapper(
        .item    = Resource(.counter = counter)
        .sibling = Resource(.counter = counter)
        .whole   = whole
    )
}

main() -> (.status_code: Int32 = 0) := {
    counter :: Counter = Counter()
    whole :: Counter = Counter()
    {
        owner :: Wrapper = Wrapper(
            .item    = Resource(.counter = $&counter)
            .sibling = Resource(.counter = $&counter)
            .whole   = $&whole
        )
        replace_incomplete(.owner = $&owner, .counter = $&counter, .whole = $&whole)
    }
    if whole.count != 1 or counter.count != 4 or tokens != 1 { abort }
    {
        owner :: Wrapper = Wrapper(
            .item    = Resource(.counter = $&counter)
            .sibling = Resource(.counter = $&counter)
            .whole   = $&whole
        )
        deinit(.self = $&owner.item)
    }
    if whole.count != 1 or counter.count != 6 { abort }
    status_code = 42
}
