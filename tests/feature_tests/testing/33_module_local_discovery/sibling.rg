choose := () -> (.ok: Bool = true) {}

#if choose() {
    test sibling := () -> !() {
        testing.expect(true)!
    }
}
