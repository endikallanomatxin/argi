Pair : Type = (.first: Int32, .second: Int32)
foreign_value(.value: Pair) -> () : CFunction(.export = true) := {}
main() -> (.status_code: Int32 = 0) := {}
