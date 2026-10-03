_view_matches(.actual: ?StringView, .expected: StringView) -> (.ok: Bool) := {
    match actual {
        ..none { ok = false }
        ..some payload { ok = payload.value == expected }
    }
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    drive ::= Path(.view = "C:\\file.txt") | unwrap_or_abort(_)
    if is_absolute(&drive).ok {
    } else { status_code = 1
        return }
    if _view_matches(parent(&drive).value, "C:\\").ok {
    } else { status_code = 2
        return }
    if _view_matches(file_name(&drive).value, "file.txt").ok {
    } else { status_code = 3
        return }

    relative ::= Path(.view = "C:file.txt") | unwrap_or_abort(_)
    if is_absolute(&relative).ok { status_code = 4
        return }
    unc ::= Path(.view = "\\\\server\\share\\file.txt") | unwrap_or_abort(_)
    if _view_matches(parent(&unc).value, "\\\\server\\share\\").ok {
    } else { status_code = 5
        return }
    root ::= Path(.view = "\\\\server\\share") | unwrap_or_abort(_)
    if file_name(&root).value? { status_code = 6
        return }
    if _view_matches(parent(&root).value, "\\\\server\\share").ok {
    } else { status_code = 7
        return }
}
