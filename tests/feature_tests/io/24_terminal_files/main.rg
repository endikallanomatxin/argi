main(.system: System) -> (.status_code: Int32 = 0) := {
    if is_open(.self = $&system.terminal&.stdin).ok {
    } else { status_code = 1 return }
    if is_open(.self = $&system.terminal&.stdout).ok {
    } else { status_code = 2 return }
    if is_open(.self = $&system.terminal&.stderr).ok {
    } else { status_code = 3 return }
    if UIntNative(.value = $&system.terminal&.stdin) == UIntNative(.value = $&system.terminal&.stdout) {
        status_code = 4
        return
    }
    if UIntNative(.value = $&system.terminal&.stdout) == UIntNative(.value = $&system.terminal&.stderr) {
        status_code = 5
    }
}
