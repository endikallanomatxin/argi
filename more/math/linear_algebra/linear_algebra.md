Link against BLAS and LAPACK.
- What they provide: the foundation for dense linear algebra (vector and matrix multiplication, plus advanced decompositions).
- Why they matter: nearly all scientific, machine learning, and numerical simulation software (MATLAB, R, Julia, NumPy/SciPy, PETSc…) uses them under the hood to deliver performance across CPUs.

Check whether they are installed on the system, in order of preference.
If none are installed, suggest a command to install them.


Julia seems very good for working with arrays, vectors, and related structures.

> [!TODO] Choose a name for the most general type.

```
NDVector : Abstract = (
	.type : Type
	.data : Ptr
	.n_dim : UIntNative
	...
)

Implementors of `NDVector`:
- `Vector`
- `Matrix`
```

```
v :: Vector = [1, 2, 3]
-- Becomes
v ::= Vector((1, 2, 3))
```

```
m :: Matrix = [[1, 2, 3], [4, 5, 6]]
```

Both Vector and Matrix have additional information about their orientation.
They are coherent with that when doing operations.


Dot product:
```
v1 ::= Vector((1, 2, 3))
v2 ::= Vector((4, 5, 6))

-- Opciones
v1|dot(v2) == 32
v1 * v2|transpose == 32
```

Cross product:
```
v1 ::= Vector((1, 2, 3))
v2 ::= Vector((4, 5, 6))

v1|cross(v2) == Vector([-3, 6, -3])
```

Matrix types:

```
Matrix : Abstract = (
	...
)

Implementors of `Matrix#(.t: Type)`:
- `RectangularMatrix`  -- Square also, but generally rectangular
- `IdentityMatrix`
- `ZeroMatrix`
- `UpperTriangularMatrix`
- `LowerTriangularMatrix`
- `DiagonalMatrix`
- `SymmetricMatrix`
- `AntiSymmetricMatrix`
- `OrthogonalMatrix`  -- ?
- `UnitaryMatrix`  -- ?
- `HermitianMatrix`  -- ?
```

```
i := IdentityMatrix(3)
```

```
Vector : Abstract = (
	...
)

Implementors of `Vector`:
- `GeneralVector`
- `OnesVector`
- `ZerosVector`
- `OneHotVector`  -- Contains one 1; the rest are 0. Enables many optimizations.
- `ManyHotVector` -- Contains several 1s; the rest are 0.
```


**Linear algebra functions**

```
det(), inv(), eig(), qr(), lu(), norm()
```

How data is stored in memory can matter for operation efficiency.

```
m|to_stack
m|to_column_major
```

This must be configurable during initialization.
```
m := Matrix(((1, 2, 3),
	     (4, 5, 6)),
		 storage_implementation = ..ColumnMajor)
```

Supported options:

- storage_implementation: column_major, row_major, stack. (default: column_major)
- definition_inner_orientation: row, column. (default: row)

Optimize using BLAS and LAPACK.
