Value : Type = (
    .items: [2]Int32
)

main() -> (.status_code: Int32) := {
    value :: Value = (.items = (7, 8))
    pointer ::= $&value

    if pointer&.items[0] != 7 {
        status_code = 1
        return
    }
    pointer&.items[1] = 9
    if pointer&.items[1] != 9 {
        status_code = 2
        return
    }
    status_code = 0
}
