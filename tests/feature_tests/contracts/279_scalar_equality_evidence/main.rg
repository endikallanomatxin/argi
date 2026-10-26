same := <.T: Type> (.left: T, .right: T) -> (.ok: Bool) {
    ok = left == right
}

main := () -> (.status_code: Int32 = 0) {
    narrow :: UInt8 = 7
    if narrow != 7 or narrow == 8 { status_code = 1 }
    if true != true or false == true { status_code = 2 }
    if same(narrow, 7) == false { status_code = 3 }
    scalar :: Float32 = 1.5
    if scalar != 1.5 or same(scalar, scalar) == false { status_code = 4 }
    zero :: Float32 = 0.0
    nan :: Float32 = zero / zero
    if nan == nan or nan != nan == false { status_code = 5 }
    qualified ::= Equal<UInt8, UInt8, (.left: UInt8, .right: UInt8)>.equal(
        .args = (.left = narrow, .right = 7)
    )
    if qualified == false { status_code = 6 }
}
