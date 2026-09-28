Box : Type = (
    .item: &Int32
)

main() -> (.status_code: Int32) := {
    first :: Int32 = 1
    second :: Int32 = 2
    box :: Box = (.item = &first)
    box.item = &second
    copied ::= box
    if copied.item& == 2 {
        status_code = 0
    } else {
        status_code = 1
    }
}
