fail() -> !Void = ..ok Void() := {}
finish#(.t: Type)(.value: t) -> (.result: Int32 = 0) := { #defer { fail()!!! { result = 1 } } }
main() -> () := { finish#(.t: Int32)(1) }
