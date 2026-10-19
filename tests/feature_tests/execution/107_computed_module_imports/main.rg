choose := () -> (.ok: Bool) { ok = true }

#if choose() {
    dependency := import ("./dependency")
    main := () -> (.status_code: Int32) { status_code = dependency.answer() }
} #else {
    missing := import ("./does_not_exist")
}
