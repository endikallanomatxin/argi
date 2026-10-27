OrderPolicy := (.reversed: Bool)

Rank := (.value: Int32, .policy: &OrderPolicy)

implement Compare#(&Rank, &Rank) (
    .compare = (.left: &Rank, .right: &Rank) -> (.order: Ordering) {
        if left&.policy&.reversed {
            order = Compare#(Int32, Int32).compare(
                .left = right&.value, .right = left&.value
            ).order
        } else {
            order = Compare#(Int32, Int32).compare(
                .left = left&.value, .right = right&.value
            ).order
        }
    }
)

ordered := #(.T: Type) (.a: &T, .b: &T) -> (.ok: Bool) { ok = a < b }

main := () -> (.status_code: Int32 = 0) {
    policy: OrderPolicy = (.reversed = true)
    a: Rank = (.value = 9, .policy = &policy)
    b: Rank = (.value = 3, .policy = &policy)
    if [&a < &b] == false { status_code = 1 }
    if ordered(&a, &b).ok == false { status_code = 2 }
}
