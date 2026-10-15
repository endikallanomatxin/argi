Large : CStruct = (.first: CLongLong, .second: CLongLong, .third: CLongLong)
_result() -> (.value: Large) : CFunction(.symbol = "argi_c_conflict")
_argument(.value: &Large) -> () : CFunction(.symbol = "argi_c_conflict")
main() -> (.status_code: Int32 = 0) := { }
