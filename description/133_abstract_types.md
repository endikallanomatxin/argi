# Abstract types

Abstract types should be one of the main reusable abstraction mechanisms of the
language. They are primarily for expressing static contracts.

- They let you define which functions must be callable on a type.

- They require explicitly specifying which types underlie the abstract type.

- They let you define a default type, which is initialized when the abstract is
  used as a declared type.

- They do NOT allow properties (to avoid bad practices).

- They can be composed.

- They may be extended outside their source modules; visibility and
  authorization rules remain open questions.

- When used in a function signature, they are monomorphized by default. Use
  `Virtual#(AbstractType)` for dynamic dispatch at runtime.

- Concrete types implementing an abstract may have extra comptime parameters,
  but must explicitly map the abstract's parameters in the abstract contract.

## Associated parameters

The parameters of an abstract are compile-time information associated with the
implementing type. For each concrete pair `(Self, Abstract)`, resolution must
produce one unique argument vector:

```text
(Self, Abstract) -> [GenericArgValue]
```

They do not select among multiple implementations. Several composition paths
may prove the same implementation when they produce equal arguments; paths
that produce different arguments conflict.

Associated parameters are not limited to types. They use the same compile-time
argument domain as generics, so an abstract may associate both types and values
such as integer dimensions. For example, `AbstractMatrix#(.t: Type, .rows:
UIntNative, .cols: UIntNative)` associates all three values with each concrete
matrix type.

Inference is deliberately directional. The compiler first infers `Self`, then
resolves its abstract implementation, and finally binds or checks the
associated parameters. It never searches backwards from an associated
parameter to discover a possible `Self`. Relations that genuinely need several
independently selected types belong in multiple dispatch, with `where(...)`
reserved as a possible future constraint mechanism.

For example, resolving `FalliblyCopyable` for a type determines its unique
`.reasons` choice, while resolving `Iterator` determines its unique `.t`.


## Declaration

Inside an abstract body, `Self` can be used as the implementing type.


An abstract is declared like this:

```
Animal : Abstract = (
	-- Functions use currying syntax.
	speak(.who: Self) -> (.text: String)
)

speak (.d: Dog) -> (.s: String) := {
	return "Woof"
}

-- Requires an explicit implementation declaration.
Dog implements Animal

-- Allows defining a default value.
Animal defaultsto Dog
```

> [!QUESTION] Valorar default
> Since convenient syntax for defining lists at the end is not planned,
> perhaps this is not useful.

```
Addable : Abstract = (
	operator + (.left: Self, .right: Self) -> (.result: Self)
)
```

The named collection contracts currently defined in `core/lists/List.rg` are:

```
Indexable#(.t: Type) : Abstract = (
	length(.self: &Self) -> (.count: UIntNative)
	get_ro_ref(.self: &Self, .index: UIntNative) ->
	    (.result: Errable#(.t: &t, .reasons: (..out_of_bounds)))
)

IndexableMutable#(.t: Type) : Abstract = (
	length(.self: &Self) -> (.count: UIntNative)
	get_ro_ref(.self: &Self, .index: UIntNative) ->
	    (.result: Errable#(.t: &t, .reasons: (..out_of_bounds)))
	get_rw_ref(.self: $&Self, .index: UIntNative) ->
	    (.result: Errable#(.t: $&t, .reasons: (..out_of_bounds)))
)

IndexableValue#(.t: Type: ImplicitlyCopyable) : Abstract = (
	get(.self: &Self, .index: UIntNative) ->
	    (.result: Errable#(.t: t, .reasons: (..out_of_bounds)))
)

Resizable#(.t: Type) : Abstract = (
	push(.self: $&Self, .value: t, .allocator: $&Allocator) ->
	    (.result: Errable#(.t: Void, .reasons: (..out_of_memory)))
	pop(.self: $&Self) ->
	    (.result: Errable#(.t: t, .reasons: (..empty)))
	insert(.self: $&Self, .i: UIntNative, .value: t,
	       .allocator: $&Allocator) ->
	    (.result: Errable#(.t: Void,
	                      .reasons: (..out_of_memory, ..out_of_bounds)))
	remove(.self: $&Self, .i: UIntNative) ->
	    (.result: Errable#(.t: t, .reasons: (..out_of_bounds)))
)
```

`DynamicArray` exposes corresponding functions, but does not yet declare an
explicit `implements Resizable` relationship.

To compose them:

```
Number : Abstract = (
    Addable
    Substractable
    Multiplicable
    -- You can mix functions and other Abstract here.
)
```

Cases:

- When a function takes more than one abstract type, types are not assumed to
be the same, to express that, use compile-time-parameters.

    ```
    foo#(.t: Type: ExampleAbstract) (.a: t, .b: t) -> (.r: t) := { ... }
    ```

    All function calls using abstracts could in fact be expressed with
    generics. Abstracts are convenient in the common case where nothing is
    assumed about the input.


- When specifying an interaction between two types from abstracts to more
concrete types, multiple dispatch will choose the most specific one. So, it is
important not only that the compiler checks that the type implements the
abstract contract, but it also has to check that no other function with the
same name and compatible input types breaks the contract.

This is one of the areas where it is worth preferring simpler rules over more
expressive ones. If the interaction between abstracts, generics and multiple
dispatch becomes difficult to explain, the design should be narrowed.


## Expresiveness

Abstract types in Julia are extremely flexible and powerful while being easy to
use. To have those simultaneously, they are just nominal. Thus, the languaje
doesn't know about what functions you can call with the abstract types. You
just call, and wait for the error at runtime.

If we want to have the same flexibility and power but with compile-time checking, we
need to have a way to express the possible interoperability between abstract types.


Challlenge for expresssiveness 1: "Abstract Matrices that interoperate".

```
AbstractMatrix#(.t: Type) : Abstract = (

    -- Closed under addition
    operator + (.left: Self, .right: Self) -> (.result: Self)

    -- Closed under multiplication
    operator * (.left: Self, .right: Self) -> (.result: Self)

    -- Multiplicable with other AbstractMatrix types:
    operator * (.left: Self, .right: AnyOther#(.t: t)) -> (.result: SomeOther#(.t: t))
    -- If you don't want to implement it with all other AbstractMatrix types,
    -- you can provide a default implementation that uses conversion to DenseMatrix.
)
```

Challenge for expressiveness 2: "Abstract Matrices that check dimensions at
compile time".


```
AbstractMatrix#(
    .t             : Type
    .indexing_type : Type:UInt
    .rows          : indexing_type
    .cols          : indexing_type
) : Abstract = (

    -- Rows and cols
    n_rows(.m: Self) -> (.n: indexing_type)
    n_cols(.m: Self) -> (.n: indexing_type)


    -- Get item
    get (.m: &Self, .i: IndexingSpec) -> (.r: Errable#(.t: t, .reasons: (..out_of_bounds)))

    -- Set item
    set (.m: $&Self, .i: IndexingSpec, .v: t) -> (.r: Errable#(.t: Void, .reasons: (..out_of_bounds)))


    -- Addable with other matrix types of the same shape
    operator + (
        .left  : Self
	.right : AnyOther#(.t: t, .rows = rows, .cols = cols)
    ) -> (
	.result: SomeOther#(.t: t, .rows = rows, .cols = cols)
    )

    -- Multiplicable with other compatible AbstractMatrix types:
    operator * #(
        .right_matrix_cols: indexing_type
    ) (
        .left  : Self
        .right : AnyOther#(.t: t, .rows = cols, .cols = right_matrix_cols)
    ) -> (
        .result: SomeOther#(.t: t, .rows = rows, .cols = right_matrix_cols)
    )
)
```

---

> [!QUESTION] The visibility and orphan rules for external `implements` remain
> open alongside cross-module overload lookup; see `131_multiple_dispatch.md`.

> [!QUESTION] Subtyping with generics.
> Can `Vector<Int64>` be used where `Vector<Number>` is expected?


> [!QUESTION] Where clauses in function and abstract headers.
> Consider whether this is worthwhile.

> [!QUESTION]
> Can an abstract provide associated types?
