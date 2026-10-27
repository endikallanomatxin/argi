main := (.system: System) -> (.status_code: Int32 = 0) {
    if is_open(.self = $&system.terminal&.stdin).ok {
    } else {
        status_code = 1
        return
    }
    if is_open(.self = $&system.terminal&.stdout).ok {
    } else {
        status_code = 2
        return
    }
    if is_open(.self = $&system.terminal&.stderr).ok {
    } else {
        status_code = 3
        return
    }
    if [
        $&system.terminal&.stdin | convert#(.to: UIntNative)(_)
        == $&system.terminal&.stdout | convert#(.to: UIntNative)(_)
    ] {
        status_code = 4
        return
    }
    if [
        $&system.terminal&.stdout | convert#(.to: UIntNative)(_)
        == $&system.terminal&.stderr | convert#(.to: UIntNative)(_)
    ] {
        status_code = 5
    }
}
