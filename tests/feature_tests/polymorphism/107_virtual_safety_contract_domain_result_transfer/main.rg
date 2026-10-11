Source: Abstract = (
    domain storage
    get(.self: &Self) -> (.value: &Int32) where depends_on(value, self.storage)
    reset(.self: $&Self) -> () where invalidates(self.storage)
)

Cell: Type = (.value: Int32)

Cell implements Source where { storage(self.value) }

get(.self: &Cell) -> (.value: &Int32) := { value = &self&.value }

reset(.self: $&Cell) -> () := { self&.value = 42 }

Relay: Abstract = (
    forward(.self: &Self, .source: Virtual#(Source)) -> (.value: Virtual#(Source))
    where transfers(value, source)
)

RelayCell: Type = (.unused: Int32)

RelayCell implements Relay

forward(.self: &RelayCell, .source: Virtual#(Source)) -> (.value: Virtual#(Source)) := {
    value = ~source
}

forward_again(.relay: &Virtual#(Relay), .source: Virtual#(Source)) -> (.value: Virtual#(Source)) := {
    value = forward(relay, ~source)
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(41)
    relay_cell ::= RelayCell(0)
    relay ::= to_virtual#(Relay)(&relay_cell)
    source ::= to_virtual#(Source)($&cell)
    forwarded ::= forward_again(&relay, ~source)
    old ::= get(&forwarded)
    if old&!= 41 { status_code = 1 }
    reset($&forwarded)
    current ::= get(&forwarded)
    if current&!= 42 { status_code = 1 }

}
