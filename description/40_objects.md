### NO OOP

No hay objetos.

Para dar la comodidad de llamar a métodos de objetos con un punto, se puede usar el pipe operator.

```
obj | method  -- como hacer obj.method()
```

Para recibir referencias a métodos, se usa el pipe operator con un ampersand.

```
length(&v: Vector) := Float {
    return sqrt(v.x^2 + v.y^2 + v.z^2)
}

my_vect = Vector(1, 2, 3)
my_vect|length
```


Para hacer el análogo \_\_init\_\_:

```
Expr : Type = struct [
    ---
    An expression type for symbolic stuff
    ---
    _s:   String -- The string the user put
    _ast: Tree   -- The AST generated by the program
]

init(#t: Type == Expr, s: String) := Expr {
    ast = create_ast_from_sym_s(s)
    return Expr(s, ast)
}

my_expr : Expr = "x^2"
```

Con más info en el nombre si requieren desambiguación:

```
Vector : Type = struct [
    x: Float
    y: Float
    z: Float
]

new_vector_cartesian(x: Float, y: Float, z: Float) := Vector {
    return Vector(x, y, z)
}

new_vector_from_polar(r: Float, theta: Float) := Vector {
    x = r * cos(theta)
    y = r * sin(theta)
    z = 0
    return Vector(x, y, z)
}

my_vect = new_vector_from_polar(2, PI)
```

Para definir el comportamiento de operadores, se usa operator overloading

```plaintext
operator + (v1: Vector, v2: Vector) := Vector {
    return Vector(v1.x + v2.x, v1.y + v2.y)
}
```


Para definir como se convierten en strings u otros castings.

```
to(v: Vector, #s:== String) := String {
    return "Vector(" + v.x + ", " + v.y + ", " + v.z + ")"
}

my_vec|to(String)
```


### Indexables

Como ofrecer la sintaxis de \[\], para que la gente la implemente en sus tipos.
En python es \_\_getitem\_\_ y \_\_setitem\_\_. Para numpy por ejemplo.
Go no tiene de estos, igual se puede prescindir.

```
Indexable(T: Type) := abstract [
    operator get[](index: Int) : T
    operator set[](index: Int, value: T)
]
```


```
Milista : Type = struct [
    elementos: List(Int)
]

operator get[](my_list: Milista, index: Int) := Int {
    return my_list.elementos[index]
}

operator set[](my_list: Milista, index: Int, value: Int) {
    my_list.elementos[index] = value
}

Indexable canbe Milista
```

```
my_list : Milista = [1, 2, 3]
print(lista[0])  -- Llama a `get`
lista[1] = 25    -- Llama a `set`
```

O igual se puede hacer con operator overloading.
