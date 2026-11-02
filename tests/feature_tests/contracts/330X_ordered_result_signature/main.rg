Rank := (.value: Int32)

implement Compare#(&Rank, &Rank) (
    .compare = (.left: &Rank, .right: &Rank) -> (.order: Int32) { order = 1 }
)

main := () -> () {}
