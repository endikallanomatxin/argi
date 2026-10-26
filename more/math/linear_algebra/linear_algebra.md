# Matrix shapes and products

Import `math/linear_algebra`. Storage is dense and row-major. `Scalar` includes
Argi's built-in signed/unsigned integers and Float16/32/64. Operands share an
exact scalar type; conversions remain explicit and arithmetic follows ordinary
scalar semantics. No BLAS, NumPy, or other native dependency is required.

## Fixed dimensions

`Vector<.n, .t>` owns an array in `.values`. `Matrix<.rows, .cols, .t>` owns a
nested array in `.values`, indexed by row then column. Both are implicitly
copyable; constructors accept matching arrays. Dimensions belong to the type.

- Vector `+`, `scale`, and `dot` preserve the scalar type.
- Matrix `+` requires matching rows and columns.
- `&left * &right` accepts R×K and K×C and returns R×C through Multiply.
- `transpose` returns C×R from R×C.

Addition selects Add evidence with explicit readonly references in Args. There
is no ordinary add overload family. Shared comptime parameters reject mismatched
shapes during semantizing. Results
own their storage and do not borrow inputs. Empty vectors have a zero dot
product; multiplication across an empty inner dimension produces zeros.

```rg
math := import("math/linear_algebra")
main := () -> (.status_code: Int32 = 0)  {
    left: math.Vector<.n = 3, .t: Float64> = (.values = (1.0, 2.0, 3.0))
    right: math.Vector<.n = 3, .t: Float64> = (.values = (4.0, 5.0, 6.0))
    product ::= math.dot(.left = &left, .right = &right)
    if product != 32.0 { abort }
}
```

`DotProduct<Left, Right>` determines its associated Result from selected
conformance: fixed vectors return their scalar directly, while dynamic vectors
return an Errable scalar. Module qualification such as `math.dot(...)` restricts
operation identities to that module; use the explicit contract operation when
several identities remain applicable. Fixed scaling and transposition use
VectorScaling and MatrixTransposition. Their allocating counterparts select
Provider jointly with the dynamic representation. MatrixAccess and VectorAccess
supply associated element context to checked coordinate operations. None of
these operations retains an ordinary overload family.

## Dynamic dimensions

`DynamicVector<.t>` and `DynamicMatrix<.t>` own private DynamicArray storage.
Their constructors copy an initialized readonly view with an explicit allocator.
A matrix additionally takes `.rows` and `.cols`; the checked product must equal
the source view's length. Overflow or incompatible dimensions return
`dimension_mismatch`; allocation failures return `out_of_memory`.

Vectors expose `length`, checked `get`/`set`, `dot`, `+`, and `scale`. Matrices
expose `shape`, checked `get`/`set`, `+`, `*`, and `transpose`. Dynamic
shape incompatibilities return `dimension_mismatch`. Addition and multiplication carry a statically inferred allocator reference
inside their Add or Multiply Args record, with a reach default. Other operations returning owners
take `.allocator`; scalar reads, writes, and dot products do not allocate.
Index errors return `out_of_bounds` without writing. No operation resizes an
existing owner or exposes mutable shape fields.

Results use separate storage, including when both operands are the same owner.
Inputs remain unchanged on shape or allocation failure. Zero-size dimensions
are preserved; zero-element operations skip iteration over large empty shapes.
Dynamic owners are not implicitly copyable and are cleaned up automatically.

## Representation-independent products

`MatrixShape<Value>` associates Element, Rows and Columns and a readonly `at`
operation. Dense matrices and `Diagonal<.n, .t>` implement it. Element reads
validate indices. `MatrixProduct<Left, Right>` infers dimensions and the
scalar type from selected shape evidence; its shared inner-dimension binding
rejects incompatible products. Args is associated with the selected operand pair;
its nominal record is shared by the protocol and operator adapters. Neither Args
nor Result introduces another conformance participant. Associated Result never
supplies dimension or element bindings.

The general product reads each representation through its shape operation and
returns a dense matrix. A more specific diagonal/diagonal implementation returns
a diagonal and multiplies only N values. Mixed dense/diagonal products use the
general algorithm. Standard Multiply conformances for the library's nominal
families delegate to that selected protocol, so `*` preserves the specialized
result type. There is no separate ordinary multiply overload family.

External representations can implement MatrixShape and use a qualified
MatrixProduct operation. Their nominal type can also provide a Multiply adapter,
following the same implementation ownership rules as other contracts.

```rg
math := import("math/linear_algebra")
product := <.A: Type, .B: Type> (.left: &A, .right: &B)
    -> (.result: math.MatrixProduct<A, B>.Result) {
    result = ~math.MatrixProduct<A, B>.multiply(
        .args = (.left = left, .right = right)
    )
}
```

Sparse storage, arbitrary strided views, decomposition algorithms and BLAS
integration remain separate work.
