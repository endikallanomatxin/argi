# Dense vectors and matrices

Import `math/linear_algebra`. Storage is dense and row-major. `Scalar` includes
Argi's built-in signed/unsigned integers and Float16/32/64. Operands share an
exact scalar type; conversions remain explicit and arithmetic follows ordinary
scalar semantics. No BLAS, NumPy, or other native dependency is required.

## Fixed dimensions

`Vector#(.n, .t)` owns an array in `.values`. `Matrix#(.rows, .cols, .t)` owns a
nested array in `.values`, indexed by row then column. Both are implicitly
copyable; constructors accept matching arrays. Dimensions belong to the type.

- Vector `add`, `scale`, and `dot` preserve the scalar type.
- Matrix `add` requires matching rows and columns.
- `multiply` accepts R×K and K×C and returns R×C.
- `transpose` returns C×R from R×C.

Shared comptime parameters reject mismatched shapes during semantizing. Results
own their storage and do not borrow inputs. Empty vectors have a zero dot
product; multiplication across an empty inner dimension produces zeros.

```rg
math := import("math/linear_algebra")
main() -> (.status_code: Int32 = 0) := {
    left: math.Vector#(.n = 3, .t: Float64) = (.values = (1.0, 2.0, 3.0))
    right: math.Vector#(.n = 3, .t: Float64) = (.values = (4.0, 5.0, 6.0))
    product ::= math.dot(.left = &left, .right = &right)
    if product != 32.0 { abort }
}
```

## Dynamic dimensions

`DynamicVector#(.t)` and `DynamicMatrix#(.t)` own private DynamicArray storage.
Their constructors copy an initialized readonly view with an explicit allocator.
A matrix additionally takes `.rows` and `.cols`; the checked product must equal
the source view's length. Overflow or incompatible dimensions return
`dimension_mismatch`; allocation failures return `out_of_memory`.

Vectors expose `length`, checked `get`/`set`, `dot`, `add`, and `scale`. Matrices
expose `shape`, checked `get`/`set`, `add`, `multiply`, and `transpose`. Dynamic
shape incompatibilities return `dimension_mismatch`. Operations returning new
owners take `.allocator`; scalar reads, writes, and dot products do not allocate.
Index errors return `out_of_bounds` without writing. No operation resizes an
existing owner or exposes mutable shape fields.

Results use separate storage, including when both operands are the same owner.
Inputs remain unchanged on shape or allocation failure. Zero-size dimensions
are preserved; zero-element operations skip iteration over large empty shapes.
Dynamic owners are not implicitly copyable and are cleaned up automatically.

Sparse matrices, arbitrary strided views, decomposition algorithms, generic
abstract representation dispatch, and BLAS integration remain separate work.
