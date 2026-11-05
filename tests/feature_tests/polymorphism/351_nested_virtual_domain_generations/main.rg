Source#(.Participant: Type): Contract = (
    domain storage
    domain sibling
    .get: (.self: &Participant) -> (.value: &Int32) where depends_on(value, self.storage)
    .other: (.self: &Participant) -> (.value: &Int32) where depends_on(value, self.sibling)
    .reset: (.self: $&Participant) -> () where invalidates(self.storage)
)
Cell := (.value: Int32, .other: Int32)
Holder := (.source: Virtual#(Source))
implement Source#(Cell) (
    .get = (.self: &Cell) -> (.value: &Int32) { value = &self&.value },
    .other = (.self: &Cell) -> (.value: &Int32) { value = &self&.other },
    .reset = (.self: $&Cell) -> () { self&.value = 42 }
) where { storage(self.value) sibling(self.other) }
check := (.holder: $&Holder) -> () {
    previous ::= get(&holder&.source)
    independent ::= other(&holder&.source)
    if previous& != 41 { abort }
    reset($&holder&.source)
    if independent& != 9 { abort }
    current ::= get(&holder&.source)
    if current& != 42 { abort }
}
main := () -> () {
    cell ::= Cell(41, 9)
    holder ::= Holder(to_virtual#(Source)($&cell))
    check($&holder)
}
