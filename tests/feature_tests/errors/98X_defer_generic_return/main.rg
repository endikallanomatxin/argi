finish#(.t: Type)(.value: t) -> () := { #defer { return } }
main() -> () := { finish#(.t: Int32)(1) }
