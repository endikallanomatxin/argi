# Compiletime-parameters

- They are monomorphized.
- They can be omitted and inferred by the compiler.
- The same system is used for types and functions.
- They can have default values.


## Syntax

### Declaration

Type and function parameters belong to their definition expression, after `:=`.
Specializing a definition binds compile-time arguments; it does not execute an
ordinary function. An alias retains the same definition identity.

```argi
Vec := #(.Element: Type, .count: UIntNative) (.values: [count]Element)

max := #(.t: Type) (.a: t, .b: t) -> (.result: t) {
    if a > b { result = a } else { result = b }
}

Vector := Vec
```

Contract participants remain on the contract declaration. An implementation's
parameters appear immediately after `implement`:

```argi
Copyable#(.Value: Type): Contract = (.copy: (.value: &Value) -> (.result: Value))
implement#(.T: Type) Copyable#(Box#(T)) (.copy = copy_box)
```

### Usage

```argi
v: Vec#(.Element: Float32, .count = 3) = (.values = (1.0, 2.0, 3.0))

r := max#(.t: Int32)(.a = x, .b = y)
```

Type applications accept positional arguments in declaration order. Positional
arguments form a prefix; named arguments may follow, but a positional argument
may not follow a named one. Explicit function specializations also accept
positional type arguments.
Each parameter can be supplied only once. Unknown names, excess arguments,
missing required arguments, and mismatched argument kinds are errors.

```argi
value: Errable#(Int32, (..unavailable)) = ..ok 42
pair: Pair#(Int32, .right: Bool) = (.left = 1, .right = true)
bytes: Array#(4, UInt8) = (0, 0, 0, 0)
```

Array dimensions can use an integer specialization parameter or a named
compile-time constant: `[count]Element` and `Array#(.n = count, .t: Element)`
resolve through the same compile-time rules. Mutable runtime values cannot
determine a type's layout.

A positional type argument is written directly; a named type argument uses
`.name: Type`. In type applications, positional integer expressions begin with a literal or
a sign; use the
named `.name = expression` form for a value identified by a comptime binding.
`Errable#(Value)` omits the reasons just like `Errable#(.t: Value)` and therefore
has an inferred error set. Supplying a reasons type retains an explicit set.


### Bounds

```argi
sum := #(.t: Type: Number#(t)) (.xs: []t) -> (.result: t)
-- t must satisfy the Number contract
```

## Constraint Design

There are two plausible paradigms for generic constraints in Argi.

The intended order is:

- start with the simpler one
- push it as far as it naturally goes through composition
- only move to the richer one if real use cases prove it necessary

### Option A: bounded type parameters

This is the compact system:

```argi
sum := #(.t: Type: Number#(t)) (.xs: []t) -> (.result: t)
BufferedReader := #(.base_type: Type: Reader#(base_type)) (...)
```

Meaning:

- `.t` is still a `Type` parameter
- `Number` or `Reader` is not the parameter type itself
- it is a static check saying that the concrete type bound to that parameter
  must satisfy the given contract

This option is attractive because it keeps everything in one place:

- `#(...)` declares the comptime parameters
- the `: Contract#(participants)` suffix checks selected conformance

This is enough for many useful cases:

- buffered wrappers over `Reader` / `Writer`
- numeric algorithms over `Number`
- generic containers constrained by `Indexable`, `Resizable`, etc.

It is also important that many structural relationships do not need any extra
constraint syntax at all. They can already be expressed by reusing the same
comptime parameters directly in the signature:

```argi
multiply := #(
    .t: Type,
    .left_rows: UIntNative,
    .shared: UIntNative,
    .right_cols: UIntNative,
)(
    .left: Matrix#(.t: t, .rows = left_rows, .cols = shared),
    .right: Matrix#(.t: t, .rows = shared, .cols = right_cols),
) -> (
    .result: Matrix#(.t: t, .rows = left_rows, .cols = right_cols)
)
```

That matters because it means matrix shapes and many other compile-time
relationships can often be modeled without a separate relational language.

Current preference:

- Argi should start with this option
- it should only be replaced if it stops being sufficient

### Option B: relational constraints with `where(...)`

If Option A stops being enough, the next step should be a separate relational
checking layer.

The core idea would be:

- `#(...)` introduces comptime variables
- `where(...)` checks relations between those variables afterwards

For example:

```argi
copy#(.r: Type, .w: Type)
where(
    Reader#(r),
    Writer#(w),
)(
    .reader: $&r,
    .writer: $&w,
) -> ()
```

The exact set of allowed predicates is still open, but if this direction is
ever taken it should be understood as:

- a checking layer over already-declared comptime parameters
- not a second, separate generics system

Its likely value would be cases that become awkward or impossible to express
cleanly with Option A alone, such as:

- expressing conformance checks outside the parameter declaration itself
- arithmetic relations between comptime values when those relations are not
  already encoded naturally in the signature
- future higher-order constraints if iterators, matrices or algebraic traits end
  up needing them

### Current stance

The language should proceed with Option A first.

Option B should stay documented as a reserved extension path for the future, but
it should not be introduced unless real library design pressure proves it is
needed.

In short:

- implement `#(.t: Type: Capability#(t))` well
- keep pushing signature-based composition first
- only add `where(...)` if the simple bounded model is no longer enough


## Interaction with Multiple Dispatch

An ordinary function name has one identity in its module, regardless of its
runtime signature or compile-time parameter shape. Generic declarations may
specialize that identity, but cannot define overload families. Contract operations
have identities within their contract; explicit participant patterns select the
most specific implementation. See [Contract dispatch](131_multiple_dispatch.md).


## Constructor parameters

`implement#(.t: Type) Init#(Box#(.t: t), BoxArgs#(t))` declares t in the
implementation scope, where BoxArgs is a nominal argument family. The target pattern and Args record select its bindings;
the requested target supplies known parameters and inputs infer remaining ones.
Implementation constraints validate those bindings. A bare `Box(.value = value)`
can infer its target parameters from Args, while Result never supplies missing
parameters or selects an implementation.

## Omitted compile-time parameters

Compile-time type and integer parameters may declare defaults, including references
to earlier parameters: `Pair#(.Left: Type, .Right: Type = Left)`.
Explicit arguments take precedence. In calls, input types infer omitted bindings
before defaults fill the remaining parameters; associated results never infer them.
Partial constructor arguments use the same Init evidence selection as complete
and fully inferred calls. Type annotations apply defaults directly. Completed
arguments retain declaration order and share identity with an explicit spelling.

## Interaction with Virtual types

* **Generics do not go in the vtable.** Vtable methods must be **monomorphic** after type erasure.
