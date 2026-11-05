Counter#(.T: Type): Contract = (
    .state: Region#(T)
    .set: Region#(T)
    .set: (.self: $&T) -> () where writes(self.state)
)
Cell := (.value: Int32)
main := () -> () {}
