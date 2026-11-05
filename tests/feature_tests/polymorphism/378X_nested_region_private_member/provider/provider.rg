Counter#(.T: Type): Contract = (
    ._state: Region#(T)
    .get: (.self: &T) -> (.result: Int32) where reads(self._state)
)
Provider := (.value: $&Int32)
implement Counter#(Provider) (
    ._state = region(self.value),
    .get = (.self: &Provider) -> (.result: Int32) { result = self&.value& }
)
read := (.self: &Virtual#(Counter)) -> (.result: Int32) {
    result = Counter#().get(self)
}
make := (.self: &Provider) -> (.result: Virtual#(Counter)) {
    result = to_virtual#(Counter)(self)
}
