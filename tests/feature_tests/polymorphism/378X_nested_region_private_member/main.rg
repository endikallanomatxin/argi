remote := import("./provider")
Counter#(.T: Type): Contract = (
    .state: Region#(T)
    .get: (.self: &T) -> (.result: Int32) where reads(self.state)
)
Wrapper := (.base: Virtual#(remote.Counter))
implement Counter#(Wrapper) (
    .state = region(self.base._state),
    .get = (.self: &Wrapper) -> (.result: Int32) { result = remote.read(&self&.base) }
)
main := () -> () {
    value :: Int32 = 42
    provider ::= remote.Provider($&value)
    wrapper ::= Wrapper(remote.make(&provider))
    outer ::= Virtual#(Counter)(&wrapper)
    _ = Counter#().get(&outer)
}
