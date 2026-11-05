Source#(.T: Type): Contract = (
    .storage: Region#(T)
    .get: (.self: &T) -> (.value: &Int32) where {
        reads(self.storage)
        depends_on(value, self.storage)
    }
    .set: (.self: $&T) -> () where {
        writes(self.storage)
        invalidates(self.storage)
    }
)
Cell := (.value: Int32)
implement Source#(Cell) (
    .storage = region(self.value),
    .get = (.self: &Cell) -> (.value: &Int32) { value = &self&.value },
    .set = (.self: $&Cell) -> () { self&.value = 42 }
)
Wrapper := (.base: Virtual#(Source))
implement Source#(Wrapper) (
    .storage = region(self.base.storage),
    .get = (.self: &Wrapper) -> (.value: &Int32) { value = Source#().get(&self&.base) },
    .set = (.self: $&Wrapper) -> () { Source#().set($&self&.base) }
)
main := () -> () {
    cell ::= Cell(41)
    wrapper ::= Wrapper(to_virtual#(Source)($&cell))
    outer ::= to_virtual#(Source)($&wrapper)
    previous ::= Source#().get(&outer)
    if previous& != 41 { abort }
    Source#().set($&outer)
    current ::= Source#().get(&outer)
    if current& != 42 { abort }
}
