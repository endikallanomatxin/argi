Alpha : Type = ()
Beta : Type = ()

implement ImplicitlyCopyable<Alpha> ()
implement ImplicitlyCopyable<Beta> ()

implement Init<Alpha, ()> (
    .Result: Type = Alpha
    .init = (.args: ()) -> (.result: Result) {
        result = ()
    }
)

implement Init<Beta, ()> (
    .Result: Type = Beta
    .init = (.args: ()) -> (.result: Result) {
        result = ()
    }
)

main := () -> (.status_code: Int32)  {
    alpha ::= Alpha()
    beta ::= Beta()
    _ ::= alpha
    status_code = 0
}
