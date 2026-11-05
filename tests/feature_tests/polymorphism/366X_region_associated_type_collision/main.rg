Counter#(.T: Type): Contract = (
    .state: Region#(T)
    .state: Type
    .set: (.self: $&T) -> () where writes(self.state)
)
Cell := (.value: Int32)
main := () -> () {}
