Counter#(.T: Type): Contract = (
    .state: Region#(T)
    .state: Region#(T)
    .set: (.self: $&T) -> () where writes(self.state)
)
Cell := (.value: Int32)
main := () -> () {}
