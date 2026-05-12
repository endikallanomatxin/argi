ExampleAbstract : Abstract = ()

Int32 implements ExampleAbstract

pick(
    .value: ExampleAbstract,
    .bonus: Int32 = 1,
) -> (.status_code: Int32) := {
    status_code = bonus
}

pick#(.t: Type)(.value: t) -> (.status_code: Int32) := {
    status_code = 2
}

main() -> (.status_code: Int32) := {
    status_code = pick(.value = 7)
}
