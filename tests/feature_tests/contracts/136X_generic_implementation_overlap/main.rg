Copyable#(.Value: Type): Contract = (.Result: Type, .copy: (.value: Value) -> (.result: Result))

implement#(.T: Type) Copyable#(T) (
    .Result : Type = T
    .copy   = (.value: T) -> (.result: Result) { result = value }
)

implement#(.U: Type) Copyable#(U) (
    .Result : Type = U
    .copy   = (.value: U) -> (.result: Result) { result = value }
)

main := () -> () { Copyable#(Int32).copy(42) }
