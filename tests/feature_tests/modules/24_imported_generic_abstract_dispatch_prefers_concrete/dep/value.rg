ExampleAbstract : Abstract = ()

Int32 implements ExampleAbstract

pick#(.t: Type: ExampleAbstract)(.value: t) -> (.status_code: Int32) := {
    status_code = 1
}

pick(.value: Int32) -> (.status_code: Int32) := {
    status_code = 2
}
