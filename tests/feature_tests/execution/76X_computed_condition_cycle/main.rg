recursive := () -> (.ok: Bool = false) {
    #if recursive() { ok = true }
}

main := () -> () { #if recursive() {} }
