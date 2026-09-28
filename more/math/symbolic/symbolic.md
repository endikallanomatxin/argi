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

Functions: `simplify(expr)`, `expand(expr)`, `factor(expr)`, `diff(expr, x)`, `integrate(expr, x)`.

**Additional modules and libraries**:

- A `sym.diff` module for automatic differentiation.
- A `sym.int` module for symbolic integration.
- A `sym.linalg` module for manipulating symbolic matrices.
- A `sym.series` module for expanding power series.
