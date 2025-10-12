It is important that:
- there is always a clear owner of each value.
- the compiler can track the lifetime of values.

When passsing arguments to functions/structs:

-  &value (READ in mojo). Reference but cannot mutate
- $&value (MUT  in mojo). Reference and can mutate
-   value (OWN  in mojo). Owned, can mutate


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


---
