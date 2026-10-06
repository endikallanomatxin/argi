retain#(.t: Type)(.value: t) -> (.result: &t) := {
    result = &value
}

main() -> (.status_code: Int32 = 0) := {
    first ::= retain#(.t: Int32)(.value = 19)
    second ::= retain#(.t: Int32)(.value = 23)
    if first&!= 19 or second&!= 23 { status_code = 1 }
}
