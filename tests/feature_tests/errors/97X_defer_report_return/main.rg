fail() -> !Void = ..ok Void() := {}
main#(.WriterType: Type: Writer#(WriterType))(.writer: $&WriterType = reach writer) -> () := { defer { fail()!!! } }
