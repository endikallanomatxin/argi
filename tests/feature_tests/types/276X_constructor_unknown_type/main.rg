MissingInitArgs: Type = ()

implement Init#(Missing, MissingInitArgs) (
    .Result : Type = Int32

    .init = MissingInitArgs -> (.result: Result) {
        result = 0
    }
)

main := () -> (.status_code: Int32 = 0) {}
