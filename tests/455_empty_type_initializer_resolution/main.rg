Alpha : Type = ()
Beta : Type = ()

init(.p: $&Alpha) -> () := {
}

init(.p: $&Beta) -> () := {
}

main() -> (.status_code: Int32) := {
    alpha ::= Alpha()
    beta ::= Beta()
    _ ::= alpha
    status_code = 0
}
