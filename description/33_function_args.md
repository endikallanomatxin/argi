It is important that:
- there is always a clear owner of each value.
- the compiler can track the lifetime of values.

When passsing arguments to functions/structs:

-  &value (READ in mojo). Reference but cannot mutate
- $&value (MUT  in mojo). Reference and can mutate
-   value (OWN  in mojo). Owned, can mutate

Passing by value means requesting an independent value. For non-trivial types
that should translate to an implicit call to `copy()`. If the type does not
implement `copy()`, using it as a value argument is a compile error and the
user must switch to `&` or `$&`.


Use:

```
foo (.pv :  &Type)
foo (.pv : $&Type)
foo (.v  :   Type)
```

Shorthand to enable the use of the argument as a value, not
cosidering the reference semantics:

```
foo (.v:  &Type&)
foo (.v: $&Type&)
foo (.v:   Type)
```

Examples:

```
print_twice (.s: String) -> () := {
    ...
}

write_to_file (.f: $&File, .content: String) -> () := {
    ...
}
```

In the first case `String` is copied on entry if needed. In the second case
`File` is passed by mutable reference because files are not expected to be
copyable.

> También tiene sentido usarlo en los access de los structs


### Default behaviour

(esto es un punto a favor de mojo)

El tema es que que sea READ by default es lo más cómodo+seguro.
Pero en nuestro lenguaje hay que ponerle &

Podríamos hacer que si lo has pasado por value, si dentro de la función no se
modifica, entonces el lsp te lo pone como & automáticamente.


### Default values for references

(esto es otro punto a favor de mojo)

Otro tema es que si pasas por read en mojo, es muy natural darle un = "default"

Pero para nosotros, darle un default requiere crear un valor en otra parte y referenciarlo.

Igual podemos establecer que los structs y los functions con argumentos por referencia inicializan lo que necesiten en el caller site.

> En mojo, argumentos por referencia mutable no pueden tener default values.
> No se muy bien por qué. Igual es solo para evitar el antipattern.


---

Mojo enforces *argument exclusivity* for mutable references. This means that if
a function receives a mutable reference to a value (such as an `mut` argument),
it can't receive any other references to the same value—mutable or immutable.
That is, a mutable reference can't have any other references that *alias* it.

For example, consider the following code example:

```mojo
fn append_twice(mut s: String, other: String):
   # Mojo knows 's' and 'other' cannot be the same string.
   s += other
   s += other

fn invalid_access():
  var my_string = "o"  # Create a run-time String value

  # error: passing `my_string` mut is invalid since it is also passed
  # read.
  append_twice(my_string, my_string)
  print(my_string)
```

This code is confusing because the user might expect the output to be `ooo`,
but since the first addition mutates both `s` and `other`, the actual output
would be `oooo`. Enforcing exclusivity of mutable references not only prevents
coding errors, it also allows the Mojo compiler to optimize code in some cases.

One way to avoid this issue when you do need both a mutable and an immutable
reference (or need to pass the same value to two arguments) is to make a copy:

```mojo
fn valid_access():
  var my_string = "o"           # Create a run-time String value
  var other_string = my_string  # Create a copy of the String value
  append_twice(my_string, other_string)
  print(my_string)
```

Note that argument exclusivity isn't enforced for register-passable trivial
types (like `Int` and `Bool`), because they are always passed by copy. When
passing the same value into two `Int` arguments, the callee will receive two
copies of the value.


## Summary

- `Type` means independent value semantics
- `&Type` means shared read access
- `$&Type` means exclusive mutable access
- non-copyable types cannot be passed as `Type`


## Reached Arguments

Some named arguments may be declared as *reached arguments*:

```argi
allocate(.allocator: $&Allocator = #reach allocator, system.allocator, .size: UIntNative) -> (.out: Allocation) := {
    ...
}
```

`#reach name` means:

- the argument is still part of the function interface
- the caller may pass it explicitly
- if the caller does not pass it explicitly, the compiler tries to satisfy it
  by reaching a variable with that exact name in the caller context

This is intended for ambient capabilities such as:

- `allocator`
- `system`
- `stdout`
- `logger`

### Resolution rules

Reached arguments are resolved by propagation through the call chain.

1. If the call site provides the argument explicitly, that value is used.
2. Otherwise, the compiler inspects the direct caller scope.
3. A reached declaration may contain one or more alternatives separated by
   commas.
4. Alternatives are tried left-to-right within the current caller scope.
5. Each alternative may be a dotted path. For example,
   `system.terminal.stdout_buffered_writer` means:
   - find `system` in the caller scope
   - then access `.terminal`
   - then access `.stdout_buffered_writer`
6. The first alternative that resolves in the current caller scope and matches
   the declared type is used.
7. If the declared type is an abstract, any value whose concrete type
   implements that abstract is valid.
8. If no alternative resolves in the current caller scope, the dependency is
   propagated upwards as if the caller itself had an extra argument declared as
   `.name = #reach ...`.
9. The same process is repeated in the next caller: inspect that caller first,
   then try the alternatives left-to-right there.
10. If the search reaches `main` and still cannot be satisfied, compilation
    fails.

The search is lexical and deterministic. It is resolved only through the
explicit alternatives declared by the function, not by “any value with a
compatible type”.

> TODO: Reusing commas here is probably a syntax mistake.
> Having reach alternatives separated with `,`, just like regular input fields
> in the same function signature, is too easy to confuse.

### Dotted paths and alternatives

Reached arguments may refer to nested capability paths:

```argi
print_line(
    .stdout: $&Writer = #reach stdout, terminal.stdout_buffered_writer, system.terminal.stdout_buffered_writer,
    .text: String,
) -> () := {
    ...
}
```

Here:

- `.` means field access inside a structured value
- `,` means ordered fallback alternatives

The example above means:

1. in the direct caller, try `stdout`
2. if that is not available, try `terminal.stdout_buffered_writer`
3. if that is not available, try `system.terminal.stdout_buffered_writer`
4. if none resolve there, move to the next caller and repeat the same order

This prefers nearby bindings over distant ones. That is intentional:

- local aliases should be able to override wider ambient capabilities
- functions can introduce a closer capability without forcing every nested call
  to rewrite its reach declaration
- tests and small scopes can inject local capabilities naturally

This makes reached arguments ergonomic while keeping resolution predictable.

### Explicit beats reached

An explicit argument at the call site always takes precedence:

```argi
foo(.allocator = temp_allocator)
```

This overrides any reached `allocator`.

### Tooling requirements

Reached arguments are meant to reduce boilerplate without hiding dependencies.
Because of that, tooling must make them visible:

- signature help should show which arguments are reached
- hover should show the effective reached dependencies of a function
- call hints should show when a call is supplying arguments implicitly via
  `#reach`

This keeps capability threading ergonomic without turning dependencies into
hidden globals.
