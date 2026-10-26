choose := () -> (.ok: Bool) { ok = true }

main := () -> () { missing_in_main() }

#if choose() {
    test selected := (.system: System) -> !() {
        testing.expect(.condition = true)!
    }
} #else {
    missing := import ("./does_not_exist")
    test discarded := () -> () { missing_in_discarded() }
}
