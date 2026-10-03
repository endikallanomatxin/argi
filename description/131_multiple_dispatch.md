# Multiple Dispatch

Functions are dispatched based on:

- the name of the function,

- the types of the input-fields

Note that:

- Input field names are not considered for dispatching (as it is possible to
omit them when calling functions).

- Compile-time-parameters are not considered for dispatching.

- return types are used to infer the resulting types, but not used for
dispatching.

- Specific value checks cannot be used for dispatching.

Thus, you cannot redefine a function with the same name and input fields, but
with different input-field names compile-time-parameters or return types.

## Cross-module dispatch (open design)

> [!QUESTION]
> Cross-module candidate visibility, external `implements`, and an orphan rule
> remain undecided.

The rules above describe how candidates are compared, but the candidate set
across modules is not yet specified. Before supporting external extensions,
decide:

- Which overloads are visible at a call site, including those from imported
  modules and the implicit `core` prelude.
- Whether a module may declare `implements` for a type and abstract defined
  elsewhere, and where that relationship is visible.
- Whether an orphan rule restricts such declarations to avoid type piracy.

These questions remain open; this section does not define extension lookup.

## Anti-pattern: adapter overloads

Multiple dispatch should model genuinely different semantic operations, not
hide routine representation adapters.

Avoid overload sets that only accept adjacent representations of the same
concept:

```rg
print(.value: String)
print(.value: StringView)
print(.value: &Char)
```

If all variants mean the same operation, pick one canonical input shape (for
example `StringView` for read-only text) and make conversions explicit at the
callsite. This keeps dispatch meaningful instead of turning it into adapter
noise.

## Constructors

`T init#(...)(...)` associates a constructor with the nominal type family `T`.
A call to `T(...)` considers only constructors associated with that family;
ordinary input-type dispatch then selects the overload. The association is
part of constructor identity, not a predicate over compile-time values.
Compile-time parameters and return types still do not distinguish overloads
within one family. Constructors do not participate in ordinary `init(...)`
function calls.
