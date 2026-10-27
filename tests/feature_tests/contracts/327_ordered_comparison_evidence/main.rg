comparisons :: Int32 = 0

Rank := (.value: Int32)

implement Compare#(&Rank, &Rank) (
    .compare = (.left: &Rank, .right: &Rank) -> (.order: Ordering) {
        comparisons = comparisons + 1
        order = Compare#(Int32, Int32).compare(.left = left&.value, .right = right&.value).order
    }
)

implement Compare#(&Rank, Int32) (
    .compare = (.left: &Rank, .right: Int32) -> (.order: Ordering) {
        comparisons = comparisons + 1
        order = Compare#(Int32, Int32).compare(.left = left&.value, .right = right).order
    }
)

ordered := #(.T: Type) (.a: &T, .b: &T) -> (.ok: Bool) {
    ok = a < b and a <= b and b > a and b >= a
}

main := () -> (.status_code: Int32 = 0) {
    a: Rank = (.value = 2)
    b: Rank = (.value = 5)
    if [&a < &b] == false or [&a <= &a] == false { status_code = 1 }
    if [&b > &a] == false or [&b >= &b] == false { status_code = 2 }
    if ordered(&a, &b).ok == false { status_code = 3 }
    if CompareRelations#(&Rank, &Rank).less_than(.left = &a, .right = &b).ok == false {
        status_code = 4
    }
    limit: Int32 = 5
    if [&a < limit] == false { status_code = 5 }
    if comparisons != 10 { status_code = 6 }
}
