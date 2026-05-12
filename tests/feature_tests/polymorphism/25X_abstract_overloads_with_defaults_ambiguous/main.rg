A : Abstract = ()

Int32 implements A

pick(.value: A, .left: Int32 = 1) -> (.status_code: Int32) := {
    status_code = left
}

pick(.value: A, .right: Int32 = 2) -> (.status_code: Int32) := {
    status_code = right
}

main() -> (.status_code: Int32) := {
    status_code = pick(.value = 7).status_code
}
