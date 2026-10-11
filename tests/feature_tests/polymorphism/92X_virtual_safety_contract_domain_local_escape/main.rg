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

borrow(.source: &Virtual#(Source)) -> (.value: &Int32) := {
    value = get(source)
}

reset_source(.source: $&Virtual#(Source)) -> () := {
    reset(source)
}

escaped() -> (.value: &Int32) := {
    cell ::= Cell(41, 9)
    source ::= to_virtual#(Source)($&cell)
    value = get(&source)
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(41, 9)
    source ::= to_virtual#(Source)($&cell)
    before ::= escaped()
    if before&!= 41 { status_code = 1 }
    reset_source($&source)
    after ::= borrow(&source)
    if after&!= 42 { status_code = 1 }
}
