-- Diagonal storage keeps only the N diagonal values.
Diagonal := #(.n: UIntNative, .t: Type: Scalar) (.values: Array#(.n = n, .t: t))

implement#(.n: UIntNative, .t: Type: Scalar) ImplicitlyCopyable#(Diagonal#(.n = n, .t: t)) ()

implement#(.n: UIntNative, .t: Type: Scalar) Init#(Diagonal#(.n = n, .t: t)) (
    .init = (.values: Array#(.n = n, .t: t)) -> (.result: Diagonal#(.n = n, .t: t)) {
        result = (.values = values)
    }
)

implement#(.n: UIntNative, .t: Type: Scalar) MatrixShape#(Diagonal#(.n = n, .t: t)) (
    .Element : Type = t
    .Rows    : Int  = n
    .Columns : Int  = n
    .at      = (.self: &Diagonal#(.n = n, .t: t), .row: UIntNative, .column: UIntNative) -> (
        .value : Element
    ) {
        if row >= n or column >= n { abort }
        value = zeroed#(.t: t)().value
        if row == column { value = self&.values[row] }
    }
)

implement#(.n: UIntNative, .t: Type: Scalar) MatrixProduct#(
    Diagonal#(.n = n, .t: t), Diagonal#(.n = n, .t: t)
) (
    .Args     : Type = MatrixProductArgs#(Diagonal#(.n = n, .t: t), Diagonal#(.n = n, .t: t))
    .Result   : Type = Diagonal#(.n = n, .t: t)
    .multiply = MatrixProductArgs#(Diagonal#(.n = n, .t: t), Diagonal#(.n = n, .t: t)) -> (
        .result : Result
    ) {
        result = (.values = zeroed#(.t: Array#(.n = n, .t: t))())
        i :: UIntNative = 0
        while i < n {
            result.values[i] = left&.values[i] * right&.values[i]
            i = i + 1
        }
    }
)

implement#(
    .n       : UIntNative,
    .columns : UIntNative,
    .t       : Type: Scalar,
    .Right   : Type: MatrixShape#(.Value: Right, .Rows = n, .Columns = columns, .Element: t)
) Multiply#(&Diagonal#(.n = n, .t: t), &Right) (
    .Result   : Type = MatrixProduct#(Diagonal#(.n = n, .t: t), Right).Result
    .multiply = MatrixProductArgs#(Diagonal#(.n = n, .t: t), Right) -> (.result: Result) {
        result = ~MatrixProduct#(
            Diagonal#(.n = n, .t: t), Right
        ).multiply(.left = left, .right = right)
    }
)
