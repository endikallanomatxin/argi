implement Init#(Missing, ()) (
    .Result: Type = Int32
    .init = (.args: ()) -> (.result: Result) {
        result = 0
    }
)
main() -> (.status_code: Int32 = 0) := {}
