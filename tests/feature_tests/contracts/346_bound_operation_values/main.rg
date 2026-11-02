identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }

int_identity := identity#(Int32)

Bound#(.T: Type): Contract = (.bound_value: _)

implement Bound#(Int32) (.bound_value = int_identity)

Fixed#(.T: Type): Contract = (.fixed_value: (.value: T) -> (.result: T))

implement Fixed#(Int32) (.fixed_value = int_identity)

pair := #(.Left: Type, .Right: Type) (.left: Left, .right: Right) -> (.result: Right) {
    result = right
}

int_pair := pair#(Int32)

Paired#(.T: Type): Contract = (.paired_value: _)

implement Paired#(Int32) (.paired_value = int_pair)

FixedPair#(.T: Type): Contract = (
    .fixed_pair : #(.Item: Type) (.left: T, .right: Item) -> (.result: Item)
)

implement FixedPair#(Int32) (.fixed_pair = int_pair)

main := () -> (.status_code: Int32 = 0) {
    known ::= #run () -> (.result: Int32) { result = bound_value(42) }
    if known != 42 or Bound#(Int32).bound_value(7) != 7 { status_code = 1 }
    if fixed_value(8) != 8 { status_code = 2 }
    if paired_value(.left = 3, .right = true) == false { status_code = 3 }
    if paired_value#(.Right: Int32)(.left = 3, .right = 9) != 9 { status_code = 4 }
    if fixed_pair(.left = 3, .right = true) == false { status_code = 5 }
}
