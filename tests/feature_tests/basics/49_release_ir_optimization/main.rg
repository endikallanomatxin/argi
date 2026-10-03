compute(.value: Int32) -> (.result: Int32) := {
    temporary :: Int32 = value + 2
    temporary = temporary * 3
    result = temporary
}
main() -> (.status_code: Int32 = 0) := {
    result := compute(12)
    if result != 42 { status_code = 1 }
}
