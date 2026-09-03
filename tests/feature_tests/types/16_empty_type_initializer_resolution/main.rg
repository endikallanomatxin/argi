Alpha : Type = ()
Beta : Type = ()

Alpha implements ImplicitlyCopyable
Beta implements ImplicitlyCopyable

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
