choose := () -> (.ok: Bool) { ok = true }

#if choose() {
    dependency := import ("./dependency")
    main := () -> () {}
}
