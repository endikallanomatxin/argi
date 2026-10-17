compute(.count: Int32) -> (.result: Int32 = 0) := {
    while result < count { result = result + 1 }
}

combine(.left: Int32, .right: Int32) -> (.result: Int32) := {
    result = left + right
}

main() -> (.status_code: Int32 = 0) := {
    status_code = #run combine(
        .left = compute(.count = 100000), .right = compute(.count = 100000)
    )
}
