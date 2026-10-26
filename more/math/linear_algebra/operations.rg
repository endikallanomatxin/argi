-- Each operation belongs to a capability; allocation is an explicit input.
DotProduct<.Left: Type, .Right: Type>: Contract = (
    .Result : Type
    .dot    : (.left: &Left, .right: &Right) -> (.result: Result)
)

VectorScaling<.Value: Type>: Contract = (
    .Element : Type
    .Result  : Type
    .scale   : (.self: &Value, .factor: Element) -> (.result: Result)
)

AllocatingVectorScaling<.Value: Type, .Provider: Type: Allocator<Provider>>: Contract = (
    .Element : Type
    .Result  : Type
    .scale   : (.self: &Value, .factor: Element, .allocator: $&Provider = reach allocator) -> (
        .result : Result
    )
)

MatrixTransposition<.Value: Type>: Contract = (
    .Result    : Type
    .transpose : (.self: &Value) -> (.result: Result)
)

AllocatingMatrixTransposition<.Value: Type, .Provider: Type: Allocator<Provider>>: Contract = (
    .Result    : Type
    .transpose : (.self: &Value, .allocator: $&Provider = reach allocator) -> (.result: Result)
)

MatrixAccess<.Value: Type>: Contract = (
    .Element : Type
    .get     : (.self: &Value, .row: UIntNative, .col: UIntNative) -> (
        .result: Errable<Element, (..out_of_bounds)>
    )
    .set : (.self: $&Value, .row: UIntNative, .col: UIntNative, .value: Element) -> (
        .result: Errable<Void, (..out_of_bounds)>
    )
)

VectorAccess<.Value: Type>: Contract = (
    .Element : Type
    .get     : (.self: &Value, .index: UIntNative) -> (.result: Errable<Element, (..out_of_bounds)>)
    .set     : (.self: $&Value, .index: UIntNative, .value: Element) -> (
        .result: Errable<Void, (..out_of_bounds)>
    )
)

implement<.rows: UIntNative, .cols: UIntNative, .t: Type: Scalar> MatrixTransposition<
    Matrix<.rows = rows, .cols = cols, .t: t>
> (
    .Result    : Type = Matrix<.rows = cols, .cols = rows, .t: t>
    .transpose = _math_transpose_fixed_matrix
)

implement<.n: UIntNative, .t: Type: Scalar> VectorScaling<Vector<.n = n, .t: t>> (
    .Element : Type = t
    .Result  : Type = Vector<.n = n, .t: t>
    .scale   = _math_scale_fixed_vector
)

implement<.n: UIntNative, .t: Type: Scalar> DotProduct<
    Vector<.n = n, .t: t>, Vector<.n = n, .t: t>
> (
    .Result : Type = t
    .dot    = _math_dot_fixed_vector
)

implement<.t: Type: Scalar, .Provider: Type: Allocator<Provider>> AllocatingVectorScaling<
    DynamicVector<.t: t>, Provider
> (
    .Element : Type = t
    .Result  : Type = Errable<DynamicVector<.t: t>, (..out_of_memory)>
    .scale   = _math_scale_dynamic_vector
)

implement<.t: Type: Scalar> DotProduct<DynamicVector<.t: t>, DynamicVector<.t: t>> (
    .Result : Type = Errable<t, (..dimension_mismatch)>
    .dot    = _math_dot_dynamic_vector
)

implement<.t: Type: Scalar> VectorAccess<DynamicVector<.t: t>> (
    .Element : Type = t
    .set     = _math_set_dynamic_vector
    .get     = _math_get_dynamic_vector
)

implement<.t: Type: Scalar, .Provider: Type: Allocator<Provider>> AllocatingMatrixTransposition<
    DynamicMatrix<.t: t>, Provider
> (
    .Result    : Type = Errable<DynamicMatrix<.t: t>, (..out_of_memory)>
    .transpose = _math_transpose_dynamic_matrix
)

implement<.t: Type: Scalar> MatrixAccess<DynamicMatrix<.t: t>> (
    .Element : Type = t
    .set     = _math_set_dynamic_matrix
    .get     = _math_get_dynamic_matrix
)
