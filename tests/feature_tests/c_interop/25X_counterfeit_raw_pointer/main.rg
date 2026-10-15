RawPointer#(.t: Type) : Type = (.address: UIntNative)
_fake(.pointer: RawPointer#(.t: UInt8)) -> () : CFunction
main() -> (.status_code: Int32 = 0) := {}
