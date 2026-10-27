Factory#(.Source: Type): Contract = (
    .Result : Type
    .make   : (.source: Source) -> (.result: Result)
)

make_value := #(.T: Type) (.source: Int32) -> (.result: T) { result = source }

implement Factory#(Int32) (
    .Result : Type = Int32
    .make   = make_value
)

main := () -> () {}
