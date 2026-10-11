fail() -> !Void = ..ok Void() := {}
main(.writer: $&Writer = reach writer) -> () := { #defer { fail()!!! } }
