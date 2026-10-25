Counter: Type = (.count: Int32 = 0)

index(.counter: $&Counter) -> (.result: UIntNative = 0) := {
    counter&.count = counter&.count + 1
}

value(.counter: $&Counter) -> (.result: Int32 = 42) := {
    if counter&.count != 2 { abort }
    counter&.count = counter&.count + 1
}

retarget(.target: $&$&Int32, .next: $&Int32) -> (.result: Int32 = 42) := {
    target&= next
}

main() -> (.status_code: Int32 = 0) := {
    counter :: Counter = Counter()
    rows :: [2][2]Int32 = (
        (1, 2),
        (3, 4)
    )
    saved := rows
    rows[index(.counter = $&counter)][index(.counter = $&counter)] = value(.counter = $&counter)
    if rows[0][0] != 42 or counter.count != 3 { abort }
    if saved[0][0] != 1 or rows[0][1] != 2 or rows[1][0] != 3 { abort }
    first :: Int32 = 1
    second :: Int32 = 2
    selected :: $&Int32 = $&first
    selected&= retarget(.target = $&selected, .next = $&second)
    if first != 42 or second != 2 or selected&!= 2 { abort }
    status_code = first
}
