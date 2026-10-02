Record : CStruct = (.value: RawPointer#(.t: CInt))
_call(.record: Record) -> () : CFunction
main() -> (.status_code: Int32 = 0) := { }
