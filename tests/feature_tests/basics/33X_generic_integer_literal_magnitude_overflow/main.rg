maximum#(.t: Type)() -> (.result: t) := { result = 18446744073709551616 }
main() -> (.status_code: Int32 = 0) := {
    value ::= maximum#(.t: UInt64)().result
}
