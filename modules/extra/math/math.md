### Math

#### Linear algebra

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

#### Complex numbers

```
Complex :: Abstract = [
	operator +(_, _) :: _
	operator -(_, _) :: _
	operator *(_, _) :: _
	operator /(_, _) :: _
	...
]

Complex canbe [Complex8, Complex16, Complex32, Complex64, Complex128]
-- El número del nombre corresponde a lo que ocupa cada COMPONENTE del número
Complex defaultsto Complex32

Number canbe Complex
```

#### Quaternions

```
Quaternion :: Abstract = [
	operator +(_, _) :: _
	operator -(_, _) :: _
	operator *(_, _) :: _
	operator /(_, _) :: _
	...
]

Quaternion canbe [Quaternion8, Quaternion16, Quaternion32, Quaternion64, Quaternion128]
Quaternion defaultsto Quaternion32

Number canbe Quaternion
```
#### Exact numbers

```
-- Para matemáticos:
Exact  -- Guarda las operaciones que llevan a un número exacto
       -- Permite verlo en LaTeX. 
```


#### Symbolic math

```
Expr :: Type = struct [
    ---
    An expression type for symbolic stuff
    ---
    s: String
    ast: Tree
]

expr(s: String) ::= Expr {
    ast = create_ast_from_sym_s(s)
    return Expr(s, ast)
}

my_expr :: Expr = expr("x^2")
```

Funciones: `simplify(expr)`, `expand(expr)`, `factor(expr)`, `diff(expr, x)`, `integrate(expr, x)`.

**Módulos y librerías adicionales**:

- Un módulo `sym.diff` para derivación automática.
- Un módulo `sym.int` para integración simbólica.
- Un módulo `sym.linalg` para manipular matrices simbólicas.
- Un módulo `sym.series` para expandir en series de potencias.

#### Uncertainty and units

```
-- Para físicos e ingenieros:
NumberWithUncertainty -- Trabajar en esto, igual interesa poder usar el signo +-
NumberWithUnits       -- Es una idea, igual viene bien para aplicaciones de ingeniería.
```

Hay que pensar que tener unidades no perjudique el desempeño. Que solo se considere para el desarollo, pero no al ejecutar.

#### Tracking probability distributions through operations

Si tienes una distribución de probabilidad y marcas sus percentiles (0..100, por ejemplo) puedes utilizar ese vector para representarla.

Puedes trackear a través de las operaciones.

- Aplicas la trasformación a los percentiles.
- Igual hay que cosiderar la deformación correspondiente también (si se estira por un factor, tiene que reducirse por el mismo factor.)


