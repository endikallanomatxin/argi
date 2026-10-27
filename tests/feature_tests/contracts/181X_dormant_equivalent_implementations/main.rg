Copy#(.T: Type): Contract = (.copy: (.source: T) -> (.result: T))

implement#(.T: Type) Copy#(T) (
    .copy = (.source: T) -> (.result: T) { result = source }
)

implement#(.U: Type) Copy#(U) (
    .copy = (.source: U) -> (.result: U) { result = source }
)

main := () -> () {}
