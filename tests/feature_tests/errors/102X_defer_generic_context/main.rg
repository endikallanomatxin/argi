fail() -> !Void = ..ok Void() := {}
finish#(.t: Type)(.value: t) -> () := { defer fail()!! "cleanup" }
main() -> () := { finish#(.t: Int32)(1) }
