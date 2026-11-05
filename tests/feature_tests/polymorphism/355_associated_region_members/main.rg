Counter#(.T: Type): Contract = (
    .state: Region#(T)
    .get: (.self: &T) -> (.result: Int32) where reads(self.state)
    .set: (.self: $&T, .value: Int32) -> () where {
        writes(self.state)
        invalidates(self.state)
    }
    .borrow: (.self: &T) -> (.result: &Int32) where {
        reads(self.state)
        depends_on(result, self.state)
    }
)
Provider := (.state: Int32, .other: Int32)
implement Counter#(Provider) (
    .state = region(self.state)
    .get = (.self: &Provider) -> (.result: Int32) { result = self&.state }
    .set = (.self: $&Provider, .value: Int32) -> () { self&.state = value }
    .borrow = (.self: &Provider) -> (.result: &Int32) { result = &self&.state }
)
Sum#(.T: Type): Contract = (
    .parts: Region#(T)
    .sum: (.self: &T) -> (.result: Int32) where reads(self.parts)
)
implement Sum#(Provider) (
    .parts = region(self.state, self.other)
    .sum = (.self: &Provider) -> (.result: Int32) { result = self&.state + self&.other }
)
main := () -> () {
    provider ::= Provider(7, 9)
    counter ::= to_virtual#(Counter)($&provider)
    sum ::= to_virtual#(Sum)(&provider)
    before ::= Counter#().borrow(&counter)
    if before& != 7 { abort }
    Counter#().set($&counter, 42)
    if Counter#().get(&counter) != 42 { abort }
    if Sum#().sum(&sum) != 51 { abort }
}
