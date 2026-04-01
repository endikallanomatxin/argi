main() -> (.status_code: Int32) := {
    present : ?Int32 = ..some(.value = 5)
    missing : ?Int32 = ..none

    left ::= present unwrap_or 1
    right ::= missing unwrap_or 7

    status_code = left + right - 12
}
