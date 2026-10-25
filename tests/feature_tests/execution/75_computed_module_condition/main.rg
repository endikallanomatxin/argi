choose := () -> (.ok: Bool) { ok = true }

#if choose() {
    #if choose() {
        main := () -> (.status_code: Int32) { status_code = 42 }
    } #else {
        main := () -> () { missing_nested()!!! }
    }
} #else {
    main := () -> () { missing_outer()!!! }
}
