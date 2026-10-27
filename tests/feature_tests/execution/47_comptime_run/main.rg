Pair := (.sum: Int32, .items: [2]Int32)

calculate := (.base: Int32) -> (.result: Pair) {
    total :: Int32 = base
    index :: Int32 = 0
    while index < 2 {
        total = total + 1
        index = index + 1
    }
    result = (.sum = total, .items = (base, total))
}

prepared := #(.Base: Int32) () -> (.result: Pair) {
    result = #run () -> (.value: Pair) { value = calculate(.base = Base) }
}

main := () -> (.status_code: Int32 = 0) {
    answer ::= #run () -> (.value: Pair) { value = prepared#(.Base = 40)() }
    if answer.items[0] != 40 { abort }
    if answer.items[1] != answer.sum { abort }
    status_code = answer.sum
}
