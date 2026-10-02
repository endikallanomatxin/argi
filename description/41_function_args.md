# Function arguments

An input declared as `Type` acquires a value. `&Type` borrows it for reading;
`$&Type` borrows it for reading and writing. The call site spells out the
borrow or ownership transfer.

Passing a named value to a by-value argument performs an implicit copy when
its type permits one. Otherwise the caller must use `copy(&value)` to
duplicate it or `~value` to move it. `&value` and
`$&value` remain explicit at the call site when the signature expects a
reference.


Use:

```
foo (.pv :  &Type)
foo (.pv : $&Type)
foo (.v  :   Type)
```

Reference arguments can use a shorthand that dereferences them in the body:

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

In the first case the caller must pass a temporary owned `String`, use
`copy(&text)`, or transfer one with `~text`; `String` is not copied implicitly.
In the second case `File` is passed by mutable reference because files are not
copyable.

> [!IDEA]
> Tooling could suggest changing an unused by-value argument to `&Type`.
> Caller-side construction might also support defaults for reference inputs.

## Summary

- `Type` means the callee acquires a value; named arguments copy implicitly
  only when the type permits it, otherwise acquisition must be explicit
- `&Type` means shared read access
- `$&Type` means mutable read/write access, not exclusive or `noalias`
- `~value` explicitly moves a named value into a `Type` argument


## Reached Arguments

Some named arguments may be declared as *reached arguments*:

```argi
allocate(.allocator: $&Allocator = reach allocator, .size: UIntNative) -> (.out: Allocation) := {
    ...
}
```

`reach name` means:

- the argument is still part of the function interface
- the caller may pass it explicitly
- if the caller does not pass it explicitly, the compiler tries to satisfy it
  by reaching a variable with that exact name in the caller context

Use `assume` for routine lexical dependencies. Use `reach` when a temporary
dependency should propagate through intermediate functions without editing
their signatures, for example:

- `allocator`
- `system`
- `reader` / `writer`
- `logger`

The same idea may also be used by operators with written operands. Collection
access uses ordinary named functions. For example, `get` needs only the array
and index; operations that allocate, such as `push`, also take an allocator:

```rg
assume allocator ::= $&GeneralPurposeAllocator(.allocator = system.page_allocator)
push(.self = $&arr, .value = 42)
value_result ::= get(.self = &arr, .index = 0).result
```

`get` returns an `Errable` with `..out_of_bounds`; it has no allocator input.
Calls to both functions follow the ordinary argument resolution rules above.

### Resolution rules

Reached arguments are resolved by propagation through the call chain.

1. If the call site provides the argument explicitly, that value is used.
2. Otherwise, the compiler inspects the direct caller scope.
3. A reached declaration may contain one or more alternatives separated by
   commas.
4. Alternatives are tried left-to-right within the current caller scope.
5. Each alternative may be a dotted path. For example,
   `system.terminal.stdout` means:
   - find `system` in the caller scope
   - then access `.terminal`
   - then access `.stdout`
6. The first alternative that resolves in the current caller scope and matches
   the declared type is used.
7. If the declared type is an abstract, any value whose concrete type
   implements that abstract is valid.
8. If no alternative resolves in the current caller scope, the dependency is
   propagated upwards as if the caller itself had an extra argument declared as
   `.name = reach ...`.
9. The same process is repeated in the next caller: inspect that caller first,
   then try the alternatives left-to-right there.
10. If the search reaches `main` and still cannot be satisfied, compilation
    fails.

The search is lexical and deterministic. It is resolved only through the
explicit alternatives declared by the function, not by “any value with a
compatible type”.

> [!QUESTION] Should reach alternatives use a separator other than commas?
> Having reach alternatives separated with `,`, just like regular input fields
> in the same function signature, is too easy to confuse.

### Dotted paths and alternatives

Reached arguments may refer to nested capability paths:

```argi
print_line(
    .writer: $&Writer = reach writer, terminal.stdout, system.terminal.stdout,
    .text: String,
) -> () := {
    ...
}
```

Here:

- `.` means field access inside a structured value
- `,` means ordered fallback alternatives

The example above means:

1. in the direct caller, try `writer`
2. if that is not available, try `terminal.stdout`
3. if that is not available, try `system.terminal.stdout`
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
  `reach`

This keeps capability threading ergonomic without turning dependencies into
hidden globals.

### Lexical assumed arguments

`assume name` enables an existing variable as a named input for subsequent
calls in the current lexical scope and nested scopes. It does not declare a
variable or evaluate an initializer. It can also prefix a normal variable
declaration, which declares and enables the binding in one statement:

```argi
assume allocator ::= $&GeneralPurposeAllocator(.allocator = system.page_allocator)
text ::= String(.capacity = 16)
```

`assume allocator := expression` is equivalent to `allocator := expression`
followed by `assume allocator`. The initializer runs once, before the new
binding becomes visible. The usual declaration rules apply: `:=` declares a
constant, `::=` declares a mutable variable, and an explicit type is allowed.
`assume allocator = expression` is not a declaration and is rejected.
`$&` or `&` applied to a newly created value materializes a temporary. In an
`assume` declaration, that temporary is bound for the enclosing scope; a
reference to it cannot escape that scope.

For each input, an explicit argument takes precedence over an assumed
variable with the same name, which takes precedence over the input's default.
An incompatible assumed variable is an error; it does not fall back to the
default. Normal argument copying, reference validity, and type rules apply.
Only inputs declared by the selected callee are supplied.

Assumptions refer to bindings, not snapshots of their values. Reassignment is
visible to later calls. A nearer declaration shadows the outer variable and
must itself be enabled with `assume` to supply omitted arguments. Leaving a
scope restores the enclosing assumptions.

Assumptions do not propagate across calls. A callee receives ordinary inputs
and must explicitly enable its own variables for calls in its body. The same
lexical inputs are available for automatic cleanup of locals declared after
`assume`.

Use `assume` for routine allocator and stream dependencies. `reach` retains
its existing propagation behavior for dependencies that need to cross
intermediate functions without editing their signatures, such as temporary
tracing or debugging output.
