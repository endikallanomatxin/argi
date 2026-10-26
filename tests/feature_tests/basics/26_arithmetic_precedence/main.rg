-- Exercise variables as well as constant expressions through syntaxing,
-- semantizing, and codegen. Array extents cover compile-time evaluation.
main := () -> (.status_code: Int32 = 0) {
    a :: Int32 = 2
    b :: Int32 = 3
    c :: Int32 = 4
    if a * b + c != 10 { status_code = 1 }
    if a + b * c != 14 { status_code = 2 }
    if 20 - 5 - 3 != 12 { status_code = 3 }
    if 24 / 4 / 2 != 3 { status_code = 4 }
    if 20 % 6 * 3 != 6 { status_code = 5 }
    if 12 / 3 + 2 * 4 != 12 { status_code = 6 }
    bytes: Array<.n = 2 * 3 + 4, .t: UInt8> = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    borrowed_view ::= view(.self = &bytes)
    if length(.self = &borrowed_view).count != 10 { status_code = 7 }
}
