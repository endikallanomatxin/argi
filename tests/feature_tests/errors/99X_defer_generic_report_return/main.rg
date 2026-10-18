fail() -> !Void = ..ok Void() := {}
finish#(.t: Type, .WriterType: Type: Writer#(WriterType))(.value: t, .writer: $&WriterType = reach writer) -> () := { defer { fail()!!! } }
main#(.WriterType: Type: Writer#(WriterType))(.writer: $&WriterType = reach writer) -> () := { finish#(.t: Int32)(1) }
