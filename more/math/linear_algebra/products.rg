MatrixProductArgs := <.Left: Type, .Right: Type> (.left: &Left, .right: &Right)

-- Shape evidence belongs to the representation, not to the multiplication
-- algorithm. Element reads preserve the borrowed matrix and validate indices.
MatrixShape<.Value: Type>: Contract = (
    .Element : Type
    .Rows    : Int
    .Columns : Int
    .at      : (.self: &Value, .row: UIntNative, .column: UIntNative) -> (.value: Element)
)

MatrixProduct<.Left: Type, .Right: Type>: Contract = (
    .Args     : Type
    .Result   : Type
    .multiply : (.args: Args) -> (.result: Result)
)

implement<.rows: UIntNative, .columns: UIntNative, .T: Type: Scalar> MatrixShape<
    Matrix<.rows = rows, .cols = columns, .t: T>
> (
    .Element : Type = T
    .Rows    : Int  = rows
    .Columns : Int  = columns
    .at      = (
        .self   : &Matrix<.rows = rows, .cols = columns, .t: T>,
        .row    : UIntNative,
        .column : UIntNative
    ) -> (.value: Element) {
        value = self&.values[row][column]
    }
)

-- The same inner dimension and element binding must satisfy both shape
-- conformances. Results never supply participant or dimension inference.
implement<
    .rows    : UIntNative,
    .inner   : UIntNative,
    .columns : UIntNative,
    .T       : Type: Scalar,
    .Left: Type: MatrixShape<.Value: Left, .Rows = rows, .Columns = inner, .Element: T>,
    .Right: Type: MatrixShape<.Value: Right, .Rows = inner, .Columns = columns, .Element: T>
> MatrixProduct<Left, Right> (
    .Args     : Type = MatrixProductArgs<Left, Right>
    .Result   : Type = Matrix<.rows = rows, .cols = columns, .t: T>
    .multiply = (.args: MatrixProductArgs<Left, Right>) -> (.result: Result) {
        result = (.values = zeroed<.t: Array<.n = rows, .t: Array<.n = columns, .t: T>>>())
        row :: UIntNative = 0
        while row < rows {
            column :: UIntNative = 0
            while column < columns {
                k :: UIntNative = 0
                while k < inner {
                    a ::= MatrixShape<Left>.at(.self = args.left, .row = row, .column = k).value
                    b ::= MatrixShape<Right>.at(
                        .self = args.right, .row = k, .column = column
                    ).value
                    result.values[row][column] = result.values[row][column] + a * b
                    k = k + 1
                }
                column = column + 1
            }
            row = row + 1
        }
    }
)

-- A standard operator conformance belongs to this nominal matrix family.
-- The representation-independent protocol remains usable by external families
-- through a qualified MatrixProduct operation or their own Multiply adapter.
implement<
    .rows    : UIntNative,
    .inner   : UIntNative,
    .columns : UIntNative,
    .T       : Type: Scalar,
    .Right: Type: MatrixShape<.Value: Right, .Rows = inner, .Columns = columns, .Element: T>
> Multiply<
    Matrix<.rows = rows, .cols = inner, .t: T>,
    Right,
    MatrixProductArgs<Matrix<.rows = rows, .cols = inner, .t: T>, Right>
> (
    .Result   : Type = MatrixProduct<Matrix<.rows = rows, .cols = inner, .t: T>, Right>.Result
    .multiply = (.args: MatrixProductArgs<Matrix<.rows = rows, .cols = inner, .t: T>, Right>) -> (
        .result : Result
    ) {
        result = ~MatrixProduct<Matrix<.rows = rows, .cols = inner, .t: T>, Right>.multiply(
            args
        )
    }
)
