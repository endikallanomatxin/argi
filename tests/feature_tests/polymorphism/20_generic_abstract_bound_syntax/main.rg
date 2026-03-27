NumberLike : Abstract = ()

Int32 implements NumberLike

double#(.t: Type: NumberLike)(.value: t) -> (.result: Int32) := {
    result = value + value
}

main() -> (.status_code: Int32) := {
    status_code = double(.value = 21)
}
