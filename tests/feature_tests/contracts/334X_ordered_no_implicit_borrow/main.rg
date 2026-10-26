Rank := (.value: Int32)

implement Compare<&Rank, &Rank> (
    .compare = (.left: &Rank, .right: &Rank) -> (.order: Ordering) {
        order = Compare<Int32, Int32>.compare(.left = left&.value, .right = right&.value).order
    }
)

main := () -> () {
    a: Rank = (.value = 1)
    b: Rank = (.value = 2)
    result ::= a < b
}
