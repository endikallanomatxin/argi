-- Missing modules and unknown symbols in discarded branches are not resolved.
#if target_os("windows") {
    platform := import("./windows")
    _platform_value() -> (.value: Int32) := { value = platform.value() }
} #else {
    platform := import("./posix")
    _platform_value() -> (.value: Int32) := { value = platform.value() }
}

#if target_arch("aarch64") {
    #if target_arch("x86_64") {
        absent := import("./does_not_exist")
        _invalid(.value: MissingType) := { missing_function() }
    }
} #else {
    #if target_arch("aarch64") {
        absent := import("./does_not_exist")
    }
}

_is_windows#(.t: Type)() -> (.result: Bool) := { result = target_os("windows") }

main() -> (.status_code: Int32 = 0) := {
    #if target_os("windows") {
        if _platform_value() != 1 { status_code = 1 }
    } #else {
        if _platform_value() != 2 { status_code = 2 }
    }
    if _is_windows#(.t: Int32)() != target_os("windows") { status_code = 6 }
    if target_os("windows") and target_os("linux") { status_code = 3 }
    if target_arch("aarch64") and target_arch("x86_64") { status_code = 4 }
    if target_abi("gnu") and target_abi("msvc") { status_code = 5 }
}
