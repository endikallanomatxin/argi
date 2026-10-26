math := import ("math/linear_algebra")

Rows := (.values: Array<2, Array<3, Int32>>)

implement math.MatrixShape<Rows> (
    .Element : Type = Int32
    .Rows    : Int  = 2
    .Columns : Int  = 3
    .at      = (.self: &Rows, .row: UIntNative, .column: UIntNative) -> (.value: Element) {
        value = self&.values[row][column]
    }
)

product := <.A: Type, .B: Type> (.left: &A, .right: &B) -> (
    .result: math.MatrixProduct<A, B, (.left: &A, .right: &B)>.Result
) {
    result = ~math.MatrixProduct<A, B, (.left: &A, .right: &B)>.multiply(
        .args = (.left = left, .right = right)
    )
}

main := () -> (.status_code: Int32 = 0) {
    left: math.Matrix<.rows = 2, .cols = 3, .t: Int32> = (
        .values = (
            (1, 2, 3),
            (4, 5, 6)
        )
    )
    right: math.Matrix<.rows = 3, .cols = 2, .t: Int32> = (
        .values = (
            (7, 8),
            (9, 10),
            (11, 12)
        )
    )
    dense: math.Matrix<.rows = 2, .cols = 2, .t: Int32> = ~[&left * &right]
    generic ::= product(&left, &right)
    custom ::= Rows(
        .values = (
            (1, 2, 3),
            (4, 5, 6)
        )
    )
    independent ::= product(&custom, &right)
    if [
        dense.values[0][0] != 58
        or dense.values[1][1] != 154
        or generic.values[1][0] != 139
        or independent.values[0][1] != 64
    ] { status_code = 1 }
    a ::= math.Diagonal<.n = 2, .t: Int32>(.values = (2, 3))
    b ::= math.Diagonal<.n = 2, .t: Int32>(.values = (5, 7))
    diagonal: math.Diagonal<.n = 2, .t: Int32> = ~[&a * &b]
    generic_diagonal: math.Diagonal<.n = 2, .t: Int32> = ~product(&a, &b)
    if diagonal.values[0] != 10 or diagonal.values[1] != 21 or generic_diagonal.values[1] != 21 {
        status_code = 2
    }
    matrix: math.Matrix<.rows = 2, .cols = 2, .t: Int32> = (
        .values = (
            (1, 2),
            (3, 4)
        )
    )
    row_scaled ::= &a * &matrix
    column_scaled ::= &matrix * &a
    if [
        row_scaled.values[0][1] != 4
        or row_scaled.values[1][0] != 9
        or column_scaled.values[0][1] != 6
        or column_scaled.values[1][1] != 12
    ] { status_code = 3 }
    empty ::= math.Diagonal<.n = 0, .t: Int32>(.values = ())
    empty_product: math.Diagonal<.n = 0, .t: Int32> = ~[&empty * &empty]
}
