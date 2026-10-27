Alpha: Type = ()

Beta: Type = ()

implement ImplicitlyCopyable#(Alpha) ()

implement ImplicitlyCopyable#(Beta) ()

implement Init#(Alpha) (
    .init = () -> (.result: Alpha) {
        result = ()
    }
)

implement Init#(Beta) (
    .init = () -> (.result: Beta) {
        result = ()
    }
)

main := () -> (.status_code: Int32) {
    alpha ::= Alpha()
    beta ::= Beta()
    _ ::= alpha
    status_code = 0
}
