-- Dense row-major owners encode compatibility in their comptime dimensions.
Vector := #(.n: UIntNative, .t: Type: Scalar) (.values: Array#(.n = n, .t: t))

Matrix := #(.rows: UIntNative, .cols: UIntNative, .t: Type: Scalar) (
    .values : Array#(.n = rows, .t: Array#(.n = cols, .t: t))
)

implement#(.n: UIntNative, .t: Type: Scalar) ImplicitlyCopyable#(Vector#(.n = n, .t: t)) ()

implement#(.rows: UIntNative, .cols: UIntNative, .t: Type: Scalar) ImplicitlyCopyable#(
    Matrix#(.rows = rows, .cols = cols, .t: t)
) ()

VectorInitArgs: Type = #(.n: UIntNative, .t: Type: Scalar) (.values: Array#(.n = n, .t: t))

implement#(.n: UIntNative, .t: Type: Scalar) Init#(
    Vector#(.n = n, .t: t), VectorInitArgs#(n, t)
) (
    .Result : Type = Vector#(.n = n, .t: t)

    .init = VectorInitArgs#(n, t) -> (.result: Result) {
        _init_values ::= values

        result = (.values = _init_values)
    }
)

MatrixInitArgs: Type = #(.rows: UIntNative, .cols: UIntNative, .t: Type: Scalar) (
    .values : Array#(.n = rows, .t: Array#(.n = cols, .t: t))
)

implement#(.rows: UIntNative, .cols: UIntNative, .t: Type: Scalar) Init#(
    Matrix#(.rows = rows, .cols = cols, .t: t), MatrixInitArgs#(rows, cols, t)
) (
    .Result : Type = Matrix#(.rows = rows, .cols = cols, .t: t)

    .init = MatrixInitArgs#(rows, cols, t) -> (.result: Result) {
        _init_values ::= values

        result = (.values = _init_values)
    }
)

implement#(.n: UIntNative, .t: Type: Scalar) Add#(
    &Vector#(.n = n, .t: t), &Vector#(.n = n, .t: t)
) (
    .Result : Type = Vector#(.n = n, .t: t)
    .add    = (.left: &Vector#(.n = n, .t: t), .right: &Vector#(.n = n, .t: t)) -> (
        .result : Result
    ) {

        result = (.values = zeroed#(.t: Array#(.n = n, .t: t))())
        i :: UIntNative = 0

        while i < n {
            result.values[i] = left&.values[i] + right&.values[i]
            i = i + 1
        }
    }
)

_math_dot_fixed_vector := #(.n: UIntNative, .t: Type: Scalar) (
    .left         : &Vector#(.n = n, .t: t),
    .right        : &Vector#(.n = n, .t: t),
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: t) {
    result = zeroed#(.t: t)()
    i :: UIntNative = 0

    while i < n {
        result = result + left&.values[i] * right&.values[i]
        i = i + 1
    }
}

_math_scale_fixed_vector := #(.n: UIntNative, .t: Type: Scalar) (
    .self: &Vector#(.n = n, .t: t), .factor: t
) -> (.result: Vector#(.n = n, .t: t)) {
    result = (.values = zeroed#(.t: Array#(.n = n, .t: t))())
    i :: UIntNative = 0

    while i < n {
        result.values[i] = self&.values[i] * factor
        i = i + 1
    }
}

implement#(.rows: UIntNative, .cols: UIntNative, .t: Type: Scalar) Add#(
    &Matrix#(.rows = rows, .cols = cols, .t: t), &Matrix#(.rows = rows, .cols = cols, .t: t)
) (
    .Result : Type = Matrix#(.rows = rows, .cols = cols, .t: t)
    .add    = (
        .left  : &Matrix#(.rows = rows, .cols = cols, .t: t),
        .right : &Matrix#(.rows = rows, .cols = cols, .t: t)
    ) -> (.result: Result) {

        result = (.values = zeroed#(.t: Array#(.n = rows, .t: Array#(.n = cols, .t: t)))())
        row :: UIntNative = 0

        while row < rows {
            col :: UIntNative = 0
            while col < cols {
                result.values[row][col] = left&.values[row][col] + right&.values[row][col]
                col = col + 1
            }
            row = row + 1
        }
    }
)

_math_transpose_fixed_matrix := #(.rows: UIntNative, .cols: UIntNative, .t: Type: Scalar) (
    .self : &Matrix#(.rows = rows, .cols = cols, .t: t)
) -> (.result: Matrix#(.rows = cols, .cols = rows, .t: t)) {
    result = (.values = zeroed#(.t: Array#(.n = cols, .t: Array#(.n = rows, .t: t)))())
    row :: UIntNative = 0

    while row < rows {
        col :: UIntNative = 0
        while col < cols {
            result.values[col][row] = self&.values[row][col]
            col = col + 1
        }
        row = row + 1
    }
}
