MatrixView : Type = (.data_p: &[2][2]Int32)

main() -> (.status_code: Int32 = 0) := {
    data : [3][3]Int32 = ((1, 2, 3), (4, 5, 6), (7, 8, 9))
    matrix : MatrixView = (.data_p = &data)
}
