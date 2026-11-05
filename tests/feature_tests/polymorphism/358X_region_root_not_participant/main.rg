Counter#(.T: Type): Contract = (
    .state: Region#(Int32)
    .set: (.self: $&T) -> () where writes(self.state)
)
Cell := (.value: Int32)
main := () -> () {}
