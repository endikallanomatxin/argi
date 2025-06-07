add_one(a: Int32) -> Int32 := {
    return a + 1
}

main() -> Int32 := {
    a := 1
    b := add_one(a)
    return b
}
