First#(.T: Type): Contract = (.choose: _)
Second#(.T: Type): Contract = (.choose: _)

implement First#(Int32) (
    .choose = (.value: Int32) -> (.result: Int32) { result = value }
)
implement Second#(Int32) (
    .choose = (.value: Int32) -> (.result: Int32) { result = value }
)

main := () -> () { result ::= choose(42) }
