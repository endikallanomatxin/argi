Inspect#(.Args: Type): Contract = (
    .inspect: (.args: Args) -> (.result: Int32)
)
implement#(.T: Type, .U: Type) Inspect#((.left: T, .right: U)) (
    .inspect = (.args: (.left: T, .right: U)) -> (.result: Int32) { result = 1 }
)
implement#(.T: Type) Inspect#((.left: Int32, .right: T)) (
    .inspect = (.args: (.left: Int32, .right: T)) -> (.result: Int32) { result = 2 }
)
main := () -> (.status_code: Int32 = 0) {
    first :: (.left: UInt8, .right: UInt8) = (.left = 1, .right = 2)
    second :: (.left: Int32, .right: UInt8) = (.left = 1, .right = 2)
    if Inspect#((.left: UInt8, .right: UInt8)).inspect(first) != 1 { abort }
    if Inspect#((.left: Int32, .right: UInt8)).inspect(second) != 2 { abort }
}
