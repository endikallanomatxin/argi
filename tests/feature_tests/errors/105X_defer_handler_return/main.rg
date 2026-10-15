fail() -> !Void = ..ok Void() := {}
main() -> () := { #defer { fail() handle error { return } } }
