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
print_twice := (.s: String) -> ()  {
    ...
}

write_to_file := (.f: $&File, .content: String) -> ()  {
    ...
}
```

In the first case the caller must pass a temporary owned `String`, use
`copy(&text)`, or transfer one with `~text`; `String` is not copied implicitly.
In the second case `File` is passed by mutable reference because files are not
copyable.

> [!IDEA]
> Tooling could suggest changing an unused by-value argument to `&Type`.

Input defaults are evaluated independently in the caller when omitted. A
reference default can create temporary storage, which lives in the enclosing
caller scope and follows the same validity rules as an explicit temporary.

## Summary

- `Type` means the callee acquires a value; named arguments copy implicitly
  only when the type permits it, otherwise acquisition must be explicit
- `&Type` means shared read access
- `$&Type` means mutable read/write access, not exclusive or `noalias`
- `~value` explicitly moves a named value into a `Type` argument


## Lexical assumed arguments

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

Use `assume` for routine allocator and stream dependencies. Every function
explicitly declares the inputs it needs; dependencies never extend a caller
signature automatically.
