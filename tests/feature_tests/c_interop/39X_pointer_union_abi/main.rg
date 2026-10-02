Value : CUnion = (.integer: CInt, .pointer: RawPointer#(.t: UInt8))
_call(.value: Value) -> () : CFunction
main() -> (.status_code: Int32 = 0) := { }
