choose_dependency := () -> (.ok: Bool) { ok = false }

#if choose_dependency() {
    missing := import ("./does_not_exist")
} #else {
    answer := () -> (.result: Int32) { result = 42 }
}
