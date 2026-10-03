Alpha : Type = ()
Beta : Type = ()

Alpha implements ImplicitlyCopyable
Beta implements ImplicitlyCopyable

Alpha init() -> (.result: Alpha) := {
    result = ()

}

Beta init() -> (.result: Beta) := {
    result = ()

}

main() -> (.status_code: Int32) := {
    alpha ::= Alpha()
    beta ::= Beta()
    _ ::= alpha
    status_code = 0
}
