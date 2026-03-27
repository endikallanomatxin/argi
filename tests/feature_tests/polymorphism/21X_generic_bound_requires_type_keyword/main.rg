ExampleAbstract : Abstract = ()

foo#(.t: Int32: ExampleAbstract)(.value: Int32) -> (.result: Int32) := {
    result = value
}

main() -> (.status_code: Int32) := {
    status_code = foo(.value = 0)
}
