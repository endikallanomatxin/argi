Pair : Type = (.first: Int32, .second: Int32)
foreign_pair(.value: Pair) -> (.result: Int32) : CFunction
main() -> (.status_code: Int32 = 0) := {}
