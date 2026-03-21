```
Expr : Type = (
    ---
    An expression type for symbolic stuff
    ---
    s: String
    ast: Tree
)

expr(.s: String) -> (.out: Expr) := {
    ast ::= create_ast_from_sym_s(s)
    out = Expr(s, ast)
}

my_expr :: Expr = expr(.s = "x^2")
```

Funciones: `simplify(expr)`, `expand(expr)`, `factor(expr)`, `diff(expr, x)`, `integrate(expr, x)`.

**Módulos y librerías adicionales**:

- Un módulo `sym.diff` para derivación automática.
- Un módulo `sym.int` para integración simbólica.
- Un módulo `sym.linalg` para manipular matrices simbólicas.
- Un módulo `sym.series` para expandir en series de potencias.
