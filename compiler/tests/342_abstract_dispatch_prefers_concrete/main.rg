ExampleAbstract : Abstract = ()

ExampleAbstract canbe Int32

pick (.value: ExampleAbstract) -> (.status_code: Int32) := {
    status_code = 1
}

pick (.value: Int32) -> (.status_code: Int32) := {
    status_code = 2
}

main () -> (.status_code: Int32) := {
    status_code = pick(.value = 123)
}
