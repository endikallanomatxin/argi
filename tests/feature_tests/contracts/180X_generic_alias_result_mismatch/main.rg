Copy#(.T: Type): Contract = (
    .Result : Type
    .copy   : (.source: T) -> (.result: Result)
)

copy_value := #(.T: Type) (.source: T) -> (.result: T) { result = source }

implement Copy#(Int32) (
    .Result : Type = UInt8
    .copy   = copy_value
)

main := () -> () {}
