ConditionalRead#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: ?Int32) where {
        on result ..some { reads(self) }
    }
)
main := () -> () {}
