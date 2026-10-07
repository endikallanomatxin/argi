Source: Abstract = (
    domain storage
    get(.self: &Self) -> (.value: &Int32) where depends_on(value, self.storage)
    reset(.self: $&Self) -> () where invalidates(self.storage)
)

Cell: Type = (.value: Int32, .other: Int32)

Cell implements Source where {
    storage(self.value)
}

get(.self: &Cell) -> (.value: &Int32) := {
    value = &self&.value
}

reset(.self: $&Cell) -> () := {
    self&.value = 42
}

borrow#(.source_type: Type: Source)(.source: &source_type) -> (.value: &Int32) := {
    value = get(source)
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(41, 9)
    before ::= borrow(&cell)
    if before&!= 41 { status_code = 1 }
    reset($&cell)
    after ::= borrow(&cell)
    if after&!= 42 { status_code = 1 }
}
