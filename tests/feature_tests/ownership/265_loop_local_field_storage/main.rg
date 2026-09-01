Entry : Type = (
    .key: Int32
    .value: Int32
)

read_key(.key: &Int32) -> (.value: Int32) := {
    value = key&
}

main() -> (.status_code: Int32 = 0) := {
    i :: Int32 = 0
    while i < 2 {
        entry ::= Entry(.key = i + 4, .value = i)
        key ::= read_key(.key = &entry.key).value
        if key != i + 4 {
            status_code = 1
            return
        }
        i = i + 1
    }
}
