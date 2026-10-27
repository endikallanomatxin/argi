Alpha: Type = ()

Beta: Type = ()

implement ImplicitlyCopyable#(Alpha) ()

implement ImplicitlyCopyable#(Beta) ()

AlphaInitArgs: Type = ()

implement Init#(Alpha, AlphaInitArgs) (
    .Result : Type = Alpha

    .init = AlphaInitArgs -> (.result: Result) {
        result = ()
    }
)

BetaInitArgs2: Type = ()

implement Init#(Beta, BetaInitArgs2) (
    .Result : Type = Beta

    .init = BetaInitArgs2 -> (.result: Result) {
        result = ()
    }
)

main := () -> (.status_code: Int32) {
    alpha ::= Alpha()
    beta ::= Beta()
    _ ::= alpha
    status_code = 0
}
