Creo que Julia es muy bueno para trabajar con arrays y vectores y demas

> [!TODO] Pensar nombre del tipo más general.

```
NDVector :: Abstract = [
	.type : Type
	.data : Ptr
	.n_dim : Int
	...
]

NDVector canbe [
	Vector
	Matrix
]
```

```
v :: Vector = [1, 2, 3]
-- Se convierte en
v ::= Vector|init([1, 2, 3])
```

```
m :: Matrix = [[1, 2, 3], [4, 5, 6]]
```

Both Vector and Matrix have additional information about their orientation.
They are coherent with that when doing operations.


Producto escalar:
```
v1 ::= Vector([1, 2, 3])
v2 ::= Vector([4, 5, 6])

-- Opciones
v1|dot(v2) == 32
v1 * v2|transpose == 32
```

Producto vectorial:
```
v1 ::= Vector([1, 2, 3])
v2 ::= Vector([4, 5, 6])

v1|cross(v2) == Vector([-3, 6, -3])
```

Tipos de matrices:

```
Matrix :: Abstract = [
	...
]

Matrix<#t::Type> canbe [
	RectangularMatrix  -- Square also, but generally rectangular
	IdentityMatrix
	ZeroMatrix
	UpperTriangularMatrix
	LowerTriangularMatrix
	DiagonalMatrix
	SymmetricMatrix
	AntiSymmetricMatrix
	OrthogonalMatrix  -- ?
	UnitaryMatrix  -- ?
	HermitianMatrix  -- ?
])
```

```
i := IdentityMatrix|init(3)
```

```
Vector :: Abstract = [
	...
]

Vector canbe [
	GeneralVector
	OnesVector
	ZerosVector
	OneHotVector  -- Solo tiene un 1. El resto son 0. Permite mucha optimización.
	ManyHotVector -- Tiene varios 1s. El resto son 0.
]
```


**Linear algebra functions**

```
det(), inv(), eig(), qr(), lu(), norm()
```

A veces es importante como se guardan los datos en memoria para que las operaciones sean más eficientes.

```
m|to_stack
m|to_column_major
```

Se tiene que poder definir al inicializar.
```
m := Matrix|init([[1, 2, 3],
		  [4, 5, 6]],
		 storage_implementation = ..ColumnMajor)
```

Que se pueda:

- storage_implementation: column_major, row_major, stack. (default: column_major)
- definition_inner_orientation: row, column. (default: row)

Optimizar usando BLAS y LAPACK.
