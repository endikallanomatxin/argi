Mode := (..first, ..second)

same := #(.T: Type) (.left: T, .right: T) -> (.ok: Bool) {
    ok = left == right
}

known ::= #run () -> (.result: Bool) {
    first: Mode = ..first
    second: Mode = ..second
    result = first != second and same(first, first)
}

main := () -> (.status_code: Int32 = 0) {
    first: Mode = ..first
    second: Mode = ..second
    if known == false or same(first, second) or same(first, first) == false { status_code = 1 }
}
