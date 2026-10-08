# Virtual types

Abstracts express static contracts and are monomorphized by default.
`Virtual#(.abstract: A)` explicitly requests runtime dispatch through the
contract `A`. It is useful for heterogeneous values and capability boundaries
such as allocators, streams, and error tracers.

## Borrowed handle

A virtual value is a borrowed handle to a concrete object implementing its
abstract, together with the method table needed to call that implementation.
Conversion does not allocate, copy the concrete object, or transfer ownership
of it. It adds neither an allocator nor a destructor to the handle.

The concrete owner remains responsible for initialization and cleanup. The
handle, references to the handle, and references returned through its methods
must obey the lifetimes of the concrete storage and any dependencies carried
by it. Keeping a virtual handle alive cannot keep an ended allocation or
storage generation alive.

The runtime representation consists of a data pointer and a vtable pointer.
These are compiler-managed, not source fields named `.data_ptr` or `.vtable`.
Programs invoke abstract methods through ordinary function calls.

> [!QUESTION]
> A stable foreign ABI, vtable slot ordering, and interoperability with externally
> constructed method tables are not specified. The two-pointer representation
> alone does not establish these guarantees.

## Creation

```rg
Shape : Abstract = (
    get_value(.self: &Self) -> (.value: Int32) where {}
    set_value(.self: $&Self, .value: Int32) -> () where {}
)
Box : Type = (.value: Int32)
Box implements Shape

get_value(.self: &Box) -> (.value: Int32) := {
    value = self&.value
}
set_value(.self: $&Box, .value: Int32) -> () := {
    self&.value = value
}

main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 42)
    shape :: Virtual#(.abstract: Shape) = to_virtual(.value = $&box)
    set_value(.self = $&shape, .value = 43)
    value ::= get_value(.self = &shape)
    if value != 43 { status_code = 1 }
}
```

`to_virtual` accepts a reference to a concrete object with an explicit
`implements` relationship and matching method implementations. Its abstract
argument can be inferred from an expected virtual result type. Without that
context, select the abstract explicitly:

```rg
shape ::= to_virtual#(.abstract: Shape)(.value = $&box)
compact ::= to_virtual#(Shape)($&box)
```

A contract containing any `$&Self` receiver requires a mutable concrete
reference at conversion. Creating a mutable wrapper around an `&T` does not
grant permission to mutate that `T`. A contract whose receivers are all
read-only accepts either `&T` or `$&T`; use a read-only contract when exposing
a read-only capability.

A named `.value` argument or a single positional reference is accepted.
Positional comptime type arguments omit the argument name. The concrete
object's implemented abstracts and the destination binding's name do not
select a target abstract: one concrete type can implement several contracts.

A pipe can borrow the result with `&_` or `$&_`:

```rg
assume tracer ::= NoopErrorTracer() | to_virtual#(ErrorTracer)($&_) | $&_
```

The concrete temporary and virtual wrapper remain alive for the enclosing
`assume` scope. Their references cannot escape that scope.

## Dispatch

Methods receive a reference to the virtual handle at the call site. Runtime
selection substitutes the concrete receiver pointer and calls the method in
that handle's table. The receiver need not be the first input; its position
comes from the abstract contract.

```rg
read_shape(.shape: &Virtual#(.abstract: Shape)) -> (.value: Int32) := {
    value = get_value(.self = shape)
}
```

A parameter declared as `Shape` requests the ordinary static abstract
mechanism. Use `Virtual#(.abstract: Shape)` explicitly when dynamic dispatch
is required. This dispatch support does not imply a general nominal
`Virtual<A> implements A` relationship.

A vtable slot has a fixed callable signature after erasure. The receiver's
concrete layout is hidden; other inputs and outputs must be usable without
knowing that layout. Ordinary scalar values, references to known types, and
explicit virtual handles can cross this boundary. A method-local generic
requiring a new instantiation at runtime cannot occupy one fixed slot.

Each method has exactly one receiver input whose type is directly `&Self` or
`$&Self`. Its name and position are unrestricted. The receiver is borrowed;
passing `Self` by value would require knowing the concrete representation.
Another input with a fixed known type may happen to match a selected concrete
implementation's type; that does not make it the receiver. The receiver's
identity follows its position in the abstract contract through erasure.
Two `Self` references in the same signature are not two interchangeable
virtual receivers: their hidden concrete types might differ, and selecting
one table cannot establish that the other argument matches its implementation.
Runtime multiple dispatch is not part of this mechanism.

`Self` cannot occur in another input or any output, including inside pointers,
arrays, aggregates, choices, or generic type arguments. This applies even to
a returned `&Self`: the concrete method returns an object pointer, whereas a
virtual handle also needs a table. Return a known type or an explicit virtual
handle instead. References to known receiver fields remain valid outputs;
their lifetimes still depend on the receiver.

An explicit `Virtual<A>` input or output has a known representation and does
not request another erased `Self` receiver. It may carry a different concrete
implementation without an implicit same-type relation. A method may dispatch
through that handle separately.

Associated type and value parameters must be fixed by the virtual contract's
type before a table is constructed. They cannot vary implicitly with the
runtime concrete implementation or require method specialization at a call
site. A method-local generic does not define one fixed virtual slot. These
restrictions apply to virtual use; ordinary static abstract contracts may
continue to use concrete `Self` types and compile-time specialization.

Fallible methods carry a uniform error-tracer capability input, including
implementations that always succeed. Errors created by a selected method
therefore follow the same capability rules as static calls.

Receiver and `Self` restrictions apply at virtual conversion and dispatch,
including methods that are never called but occupy a table slot. Virtual
conversion supports parameterized abstracts with fully bound type and value
arguments. Method-local generic parameters do not define virtual slots.

## Safety across implementations

Dynamic dispatch retains safety obligations. A method may return a reference
borrowed from its receiver, mutate caller-visible storage, or have effects on
owned or opaque storage. Those effects must remain valid through erasure.

An abstract method can publish a safety contract after its signature:

```rg
Source: Abstract = (
    get(.self: &Self) -> (.value: &Int32)
        where depends_on(value, self)
)
Counter: Abstract = (
    increment(.self: $&Self) -> () where {}
)
```

`depends_on(output, input, ...)` permits the named output to carry validity
dependencies from the named inputs. This permission applies transitively through
fields, choice payloads and opaque values. A reference input names its referent
and the referent's dependencies, not the local argument slot. An implementation
may return a value with fewer dependencies, including an independent global
reference. It cannot introduce dependencies on other inputs or on local storage
that ends on return. This clause neither transfers ownership nor prolongs any
lifetime.

Multiple clauses can appear in a `where` block. An empty block declares no output
dependencies. These contracts preserve storage generations and existing ownership;
ordinary content writes remain permitted by mutable references. They do not grant
permission to consume storage capabilities, end resources or store new hidden
dependencies. Input values must remain valid for the call, including capabilities
or references carried inside by-value arguments.

`refers_to(output, input)` guarantees that a reference output points to the same
storage as a named reference input. It also permits the corresponding validity
dependency. Both references must have the same referent type; read-only input
access cannot produce mutable output access. This relation names known input
storage, not erased `Self` or one of its private fields. Unlike `depends_on`, it
is a guarantee, so returning independent storage on another path does not comply.

```rg
Forwarder: Abstract = (
forward(.self: &Self, .input: $&Int32) -> (.value: $&Int32)
        where refers_to(value, input)
)
```

`invalidates(input, ...)` permits replacing the storage generation reached by
the named mutable reference inputs. Callers must treat existing references to
that storage as expired after the call, even when a particular implementation
only changes the contents. An implementation may have fewer effects than the
contract permits. Generation invalidation does not grant permission to destroy
owners, consume acquisition capabilities or store new hidden dependencies.

```rg
Editor: Abstract = (
    edit(.self: &Self, .target: $&Int32) -> ()
        where invalidates(target)
)
```

## Owning and fallible results

`owns(output)` permits fresh ownership in the output, including nested owning
fields and choice payloads. It grants no safe address, acquisition receipt or
permission to retain input storage. Declare validity dependencies separately.

`transfers(output, input)` guarantees transfer of a by-value input into an output
of the same type. Reference inputs cannot transfer ownership. This relation
preserves the input's structure and validity dependencies. It cannot be combined
with fresh ownership for the same output.

A choice-valued result can distinguish permissions by variant:

```rg
Factory: Abstract = (
    create(.self: &Self) -> (.result: Errable#(Item, Reasons)) where {
        on result ..ok {
            owns(result)
            depends_on(result, self)
        }
        on result ..error {
            depends_on(result, error_tracer)
        }
    }
)
```

`on output ..variant` always names the choice-valued output it selects. A method
can have several outputs, including several choices; selectors with the same
variant name on different outputs are distinct. Unknown outputs, non-choice
selectors and duplicate selectors are errors.

Within the block, the selected output denotes that variant's payload. Common
clauses remain applicable in every variant; conditional clauses add permissions
and obligations for the selected outcome. An empty conditional block does not
cancel a common dependency or invalidation permission. The implicit
`error_tracer` input can be named in dependencies of fallible methods.
No variant can authorize a reference to local storage that ends on return.

Outcome conditions describe the call's effects, rather than only its payload.
They can describe relations with other outputs and the state left in inputs and
storage domains. The caller must retain those correlations until it knows the
selected variant. Before discrimination, it must conservatively account for all
possible outcomes. Conditional guarantees do not undo effects already observed
or revive references to expired generations.

A conditional generation permission can describe a fallible edit:

```rg
Editor: Abstract = (
    edit(.self: &Self, .target: $&Int32) -> (.result: ?Int32) where {
        on result ..some { invalidates(target) }
        on result ..none {}
    }
)
```

A reference captured before this call is unavailable until its result is known.
The `..none` branch proves that this call preserved the target's generation; the
`..some` branch must account for its possible invalidation. This promise concerns
temporal validity, not unchanged contents or absence of external side effects.
The same distinction applies to explicitly mapped receiver domains.

Testing a copied or moved result identifies the same historical call. Replacing
that result loses its proof. A later invalidation remains effective even when an
older result selects a preservation branch. Aliased input names describe the same
actual storage; a preservation clause for one name cannot cancel an invalidation
through another name.

## Receiver storage domains

An abstract can name storage domains without exposing concrete fields. Its
methods refer to them through the receiver name:

```rg
Source: Abstract = (
    domain storage

    get(.self: &Self) -> (.value: &Int32)
        where depends_on(value, self.storage)
    reset(.self: $&Self) -> ()
        where invalidates(self.storage)
)

Cell: Type = (.value: Int32, .other: Int32)
Cell implements Source where {
    storage(self.value)
}
```

An implementation maps every declared domain exactly once. One mapping can name
several concrete field paths, grouped as `storage(self.first, self.second)`.
Private paths follow ordinary module visibility. Unknown fields, missing
mappings and overlapping domain paths are errors. Distinct domains must not
capture the same storage generation through aliased references. Aliases inside
one domain share that domain's invalidation obligation.

The mapping establishes no ownership and does not prolong a lifetime. A handle
uses current domain generations at a call; a returned reference captures the
generation present when it was produced. Invalidating a domain therefore expires
previous references while allowing subsequent calls through the same handle.
Unrelated domains and references to unrelated fields remain valid.

Contract checking preserves concrete paths until conformance has been checked.
Dynamic calls then use domain identities without inspecting other implementations.
Domain dependencies survive ordinary wrapper functions and local virtual
conversions. They cannot authorize returning a reference into a local receiver.

Concrete implementations must satisfy their declared contracts, including
methods never called in a concrete implementation declaration. Static abstract
selection and virtual table construction enforce the same obligations. A violation identifies the method,
offending input and contract declaration. Checking an implementation does not
depend on the bodies of other implementations. A virtual call uses the published
contract; a direct concrete call can use its more precise inferred summary.

Every method used through a virtual handle must declare a safety contract.
Use `where {}` when the method preserves storage and returns no borrowed or
owning dependencies; otherwise declare the permitted dependencies and effects.
An unannotated abstract can still select a statically known implementation,
but cannot be erased into a virtual handle. Adding an implementation does not
change the safety obligations of existing virtual calls.

Private concrete receiver fields are not fields of the virtual handle. A
returned borrow still depends on the receiver's storage; erasing its layout
must not erase that lifetime dependency. See `34_safety_model.md` for roots,
storage generations, and opaque storage.

> [!IMPLEMENTATION]
> Proving `refers_to` and `transfers` currently requires a concrete body that
> directly forwards the declared input. Intermediate calls and complex control
> flow require more precise storage identity proofs.
> Unconditional input `invalidates` currently supports no-result methods and known
> scalar reference inputs. Conditional clauses also support these inputs and mapped
> receiver domains. Neither
> form permits destroying owners or replacing their hidden dependencies.
> Results containing mapped virtual domains must preserve their identities with
> `transfers` or `refers_to`. A dependency permission alone cannot establish the
> correspondence between a returned handle and its underlying storage.
> Outcome clauses support output dependencies, fresh ownership and conditional
> generation changes. Generation refinement supports bound result discrimination
> and direct forwarding of a single choice through wrappers. More complex wrapper
> bodies conservatively join their effects. Hidden storage transitions, clauses
> affecting other outputs remain to be implemented. Nested payload selectors
> support dependencies, fresh ownership and generation changes.
> Independent payload selectors on several outputs are supported; generation
> effects requiring independent result correlations are conservatively joined.

For example, a fixed `Readable#(.item: Int32)` contract can occupy a virtual
handle. Conversion checks the concrete type's declared associated arguments,
then fixes every method signature before erasing `Self`. Handles for different
associated arguments are different types; their possible implementation sets
also remain separate during safety checking.

Nested `on` clauses follow the selected output's payload. They describe one
structural discriminant path rather than a conjunction between independent
results. For an `Errable#(?&Int32, Reasons)` output, an inner `on result ..some`
can permit `depends_on(result, self)` while `..none` has no such dependency.
Permissions on the outer payload also apply to its nested alternatives.

```argi
get(.self: &Self) -> (.result: Errable#(?&Int32, Reasons)) where {
    on result ..ok {
        on result ..some { depends_on(result, self) }
        on result ..none {}
    }
    on result ..error { depends_on(result, error_tracer) }
}
```

`owns(result)` inside a nested outcome permits fresh ownership only in that
selected payload. The implementation must declare this permission even when
an owner's fields contain only scalar values. Discarding an owning choice
runs cleanup for its active payload, including nested records and choices;
moving the payload transfers that cleanup obligation to its new owner.
A cleanup obligation alone establishes neither a fresh storage lifetime nor
permission to manufacture references or storage acquisition receipts.

Generation effects selected by a nested `on` clause require proving the complete
payload path. Selecting an outer success variant does not prove preservation
when its unresolved inner variants disagree. A preserving inner variant restores
permission to use the same pre-call generation only while that generation remains
current. Later invalidation or result replacement cannot restore an older root.
