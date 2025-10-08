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

> [!CHECK] Esto rompe un poco con el usar un struct con input?
> Aunque en realidad también tiene sentido usar en los access de los structs


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

More from mojo:



### Argument exclusivity

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

## Transfer arguments (`var` and `^`)

And finally, if you'd like your function to receive value **ownership**, add the
`var` keyword in front of the argument name.

This convention is often combined with use of the postfixed `^` "transfer"
sigil on the variable that is passed into the function, which ends the
lifetime of that variable.

Technically, the `var` keyword does not guarantee that the received value is
*the original value*—it guarantees only that the function
gets unique ownership of a value. This happens in one of
three ways:

* The caller passes the argument with the `^` transfer sigil, which ends the
  lifetime of that variable (the variable becomes uninitialized) and ownership
  is transferred into the function.

* The caller **does not** use the `^` transfer sigil, in which case, Mojo copies
  the value. If the type isn't copyable, this is a compile-time error.

* The caller passes in a newly-created "owned" value, such as a value returned
  from a function. In this case, no variable owns the value and it can be
  transferred directly to the callee. For example:

  ```mojo
  def take(var s: String):
      pass

  def main():
      take("A brand-new String!")
  ```

The following code works by making a copy of the string, because `take_text()`
uses the `var` convention, and the caller does not include the transfer sigil:

```mojo
fn take_text(var text: String):
    text += "!"
    print(text)

fn main():
    var message = "Hello"  # Create a run-time String value
    take_text(message)
    print(message)
```

```output
Hello!
Hello
```

However, if you add the `^` transfer sigil when calling `take_text()`, the
compiler complains about `print(message)`, because at that point, the `message`
variable is no longer initialized. That is, this version does not compile:

```mojo
fn main():
    var message = "Hello"  # Create a run-time String value
    take_text(message^)
    print(message)  # error: use of uninitialized value 'message'
```

This is a critical feature of Mojo's lifetime checker, because it ensures that no
two variables can have ownership of the same value. To fix the error, you must
not use the `message` variable after you end its lifetime with the `^` transfer
sigil. So here is the corrected code:

```mojo
fn take_text(var text: String):
    text += "!"
    print(text)

fn main():
    var message = "Hello"  # Create a run-time String value
    take_text(message^)
```

```output
Hello!
```

Regardless of how it receives the value, when the function declares an argument
as `var`, it can be certain that it has unique mutable access to that value.
Because the value is owned, the value is destroyed when the function
exits—unless the function transfers the value elsewhere.

For example, in the following example, `add_to_list()` takes a string and
appends it to the list. Ownership of the string is transferred to the list, so
it's not destroyed when the function exits. On the other hand,
`consume_string()` doesn't transfer its `var` value out, so the value is
destroyed at the end of the function.

```mojo
def add_to_list(var name: String, mut list: List[String]):
    list.append(name^)
    # name is uninitialized, nothing to destroy

def consume_string(var s: String):
    print(s)
    # s is destroyed here
```

### Transfer implementation details

In Mojo, you shouldn't conflate "ownership transfer" with a "move
operation"—these are not strictly the same thing.

There are multiple ways that Mojo can transfer ownership of a value:

* If a type implements the [move
  constructor](/mojo/manual/lifecycle/life#move-constructor),
  `__moveinit__()`, Mojo may invoke this method *if* a value of that type is
  transferred into a function as a `var` argument, *and* the original
  variable's lifetime ends at the same point (with or without use of the `^`
  transfer sigil).

* If a type implements the [copy
  constructor](/mojo/manual/lifecycle/life#move-constructor), `__copyinit__()`
  and not `__moveinit__()`, Mojo may copy the value and destroy the old value.

* In some cases, Mojo can optimize away the move operation entirely, leaving the
  value in the same memory location but updating its ownership. In these cases,
  a value can be transferred without invoking either the `__copyinit__()` or
  `__moveinit__()` constructors.

In order for the `var` convention to work *without* the transfer
sigil, the value type must be copyable (via `__copyinit__()`).


