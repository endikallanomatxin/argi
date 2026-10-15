Ordinary : Type = (.value: Int32)
Record#(.t: Type) : CStruct = (.value: t)
_call(.record: &Record#(.t: Ordinary)) -> () : CFunction
main() -> (.status_code: Int32 = 0) := { }
