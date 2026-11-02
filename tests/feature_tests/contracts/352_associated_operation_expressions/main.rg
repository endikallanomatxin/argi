identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }

Cell := #(.T: Type) (.value: T)

Associated#(.T: Type): Contract = (.Element: Type, .associated_value: _)

implement#(.T: Type) Associated#(Cell#(T)) (
    .Element          : Type = T
    .associated_value = identity#(Element)
)

with_offset := #(.amount: Int) (.value: Int32) -> (.result: Int32) { result = value + amount }

Offset#(.T: Type): Contract = (.Amount: Int, .offset_value: _)

implement Offset#(Int32) (
    .Amount       : Int = 3
    .offset_value = with_offset#(Amount)
)

main := () -> (.status_code: Int32 = 0) {
    if associated_value(42) != 42 { status_code = 1 }
    if Associated#(Cell#(Bool)).associated_value(true) == false { status_code = 2 }
    if offset_value(39) != 42 { status_code = 3 }
    known ::= #run () -> (.result: Int32) { result = associated_value(7) }
    if known != 7 { status_code = 4 }
}
