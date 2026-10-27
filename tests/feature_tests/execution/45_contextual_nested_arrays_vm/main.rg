Pair := (.sum: Int32, .items: [2]Int32)

Nested := (.pair: Pair)

calculate := (.base: Int32) -> (.result: Nested) {
    sum :: Int32 = base
    index :: Int32 = 0
    while index < 2 {
        sum = sum + 1
        index = index + 1
    }
    result = (.pair = (.sum = sum, .items = (base, sum)))
}

main := () -> (.status_code: Int32 = 0) {
    result ::= calculate(.base = 40)
    if result.pair.items[0] != 40 { abort }
    if result.pair.items[1] != result.pair.sum { abort }
    status_code = result.pair.sum
}
