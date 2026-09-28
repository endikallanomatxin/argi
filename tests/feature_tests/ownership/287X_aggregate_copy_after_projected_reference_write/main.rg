Box : Type = (
    .item: &Int32
)

read(.box: Box) -> (.value: Int32) := {
    value = box.item&
}

main() -> (.status_code: Int32) := {
    original :: Int32 = 1
    box :: Box = (.item = &original)
    if true {
        temporary :: Int32 = 2
        box.item = &temporary
    }
    copied ::= box
    status_code = read(.box = copied)
}
