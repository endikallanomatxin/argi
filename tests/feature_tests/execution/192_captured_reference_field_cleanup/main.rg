drops :: Int32 = 0
tokens :: Int32 = 0

Resource := (.value: Int32)

Holder := (.reference: $&Resource)

Token := (.value: Int32)

implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () { drops = drops + 1 })

implement Deinit#(Token) (.deinit = (.self: $&Token) -> () { tokens = tokens + 1 })

select_holder := (.token: Token, .holder: $&Holder) -> (.result: $&Holder) {
    owner ::= ~token
    result = holder
}

retarget := (.holder: $&Holder, .other: $&Resource) -> (.result: Resource) {
    holder&.reference = other
    result = Resource(.value = 9)
}

read := (.target: &Resource) -> (.result: Int32) { result = target&.value }

main := () -> (.status_code: Int32) {
    {
        owner :: Resource = Resource(.value = 1)
        other :: Resource = Resource(.value = 2)
        holder :: Holder = Holder(.reference = $&owner)
        token :: Token = Token(.value = 0)
        deinit(.self = $&owner)
        [select_holder(.token = ~token, .holder = $&holder)&.reference]&= retarget(
            .holder = $&holder, .other = $&other
        )
        if read(.target = holder.reference) != 2 { abort }
        if read(.target = &owner) != 9 { abort }
    }
    if drops != 3 or tokens != 1 { abort }
    status_code = 42
}
