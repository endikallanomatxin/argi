-- Dense row-major owners encode compatibility in their comptime dimensions.
Vector#(.n: UIntNative, .t: Type: Scalar): Type = (.values: Array#(.n = n, .t: t))

Matrix#(.rows: UIntNative, .cols: UIntNative, .t: Type: Scalar): Type = (
    .values : Array#(
        .n = rows,
        .t : Array#(.n = cols, .t: t)
    )
)

Vector#(.n: UIntNative, .t: Type: Scalar) implements ImplicitlyCopyable
Matrix#(.rows: UIntNative, .cols: UIntNative, .t: Type: Scalar) implements ImplicitlyCopyable

Vector init#(
        .n : UIntNative,
        .t : Type: Scalar
    )(
        .values : Array#(.n = n, .t: t)
    ) -> (
        .result : Vector#(
            .n = n,
            .t : t
        )
    ) := {
    result = (.values = values)
}

Matrix init#(
        .rows : UIntNative,
        .cols : UIntNative,
        .t    : Type: Scalar
    )(
        .values : Array#(
            .n = rows,
            .t : Array#(.n = cols, .t: t)
        )
    ) -> (
        .result : Matrix#(.rows = rows, .cols = cols, .t: t)
    ) := {
    result = (.values = values)
}

add#(
        .n : UIntNative,
        .t : Type: Scalar
    )(
        .left  : &Vector#(.n = n, .t: t),
        .right : &Vector#(.n = n, .t: t)
    ) -> (
        .result : Vector#(.n = n, .t: t)
    ) := {
    result = (.values = zeroed#(.t: Array#(.n = n, .t: t))())
    i :: UIntNative = 0
    while i < n {
        result.values[i] = left&.values[i] + right&.values[i]
        i = i + 1
    }
}

dot#(
        .n : UIntNative,
        .t : Type: Scalar
    )(
        .left  : &Vector#(.n = n, .t: t),
        .right : &Vector#(.n = n, .t: t)
    ) -> (
        .value : t
    ) := {
    value = zeroed#(.t: t)()
    i :: UIntNative = 0
    while i < n {
        value = value + left&.values[i] * right&.values[i]
        i = i + 1
    }
}

scale#(
        .n : UIntNative,
        .t : Type: Scalar
    )(
        .self   : &Vector#(.n = n, .t: t),
        .factor : t
    ) -> (
        .result : Vector#(
            .n = n,
            .t : t
        )
    ) := {
    result = (.values = zeroed#(.t: Array#(.n = n, .t: t))())
    i :: UIntNative = 0
    while i < n {
        result.values[i] = self&.values[i] * factor
        i = i + 1
    }
}

add#(
        .rows : UIntNative,
        .cols : UIntNative,
        .t    : Type: Scalar
    )(
        .left : &Matrix#(
            .rows = rows,
            .cols = cols,
            .t    : t
        ),
        .right : &Matrix#(.rows = rows, .cols = cols, .t: t)
    ) -> (
        .result : Matrix#(
            .rows = rows,
            .cols = cols,
            .t    : t
        )
    ) := {
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

multiply#(
        .rows  : UIntNative,
        .inner : UIntNative,
        .cols  : UIntNative,
        .t     : Type: Scalar
    )(
        .left : &Matrix#(
            .rows = rows,
            .cols = inner,
            .t    : t
        ),
        .right : &Matrix#(.rows = inner, .cols = cols, .t: t)
    ) -> (
        .result : Matrix#(
            .rows = rows,
            .cols = cols,
            .t    : t
        )
    ) := {
    result = (.values = zeroed#(.t: Array#(.n = rows, .t: Array#(.n = cols, .t: t)))())
    row :: UIntNative = 0
    while row < rows {
        col :: UIntNative = 0
        while col < cols {
            k :: UIntNative = 0
            while k < inner {
                result.values[row][col] = result.values[row][col] + left&.values[row][k] * right&.values[k][col]
                k = k + 1
            }
            col = col + 1
        }
        row = row + 1
    }
}

transpose#(
        .rows : UIntNative,
        .cols : UIntNative,
        .t    : Type: Scalar
    )(
        .self : &Matrix#(
            .rows = rows,
            .cols = cols,
            .t    : t
        )
    ) -> (
        .result : Matrix#(.rows = cols, .cols = rows, .t: t)
    ) := {
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
