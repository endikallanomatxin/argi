fail() -> !Void = ..ok Void() := {}
finish#(.t: Type)(.value: t, .writer: $&Writer = reach writer) -> () := { #defer { fail()!!! } }
main(.writer: $&Writer = reach writer) -> () := { finish#(.t: Int32)(1) }
