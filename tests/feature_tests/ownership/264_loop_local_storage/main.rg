main() -> (.status_code: Int32 = 0) := {
    i :: Int32 = 0
    while i < 2 {
        local ::= i + 1
        pointer ::= &local
        if pointer& != i + 1 {
            status_code = 1
            return
        }
        i = i + 1
    }
}
