calls :: Int32 = 0

next_value() -> (.result: Int32) := {
    calls = calls + 1
    result = 20 + calls
}

main() -> (.status_code: Int32) := {
    first: (.marker: Int32, .value: Int32 = next_value()) = (.marker = 1)
    second: (.marker: Int32, .value: Int32 = next_value()) = (.marker = 2)
    if calls != 2 { abort }
    reordered: (.left: Int32, .right: Int32) = (.right = second.value, .left = first.value)
    status_code = reordered.left + reordered.right - 1
}
