# Virtual types

[Contracts and conformance](135_contracts.md) defines the general evidence model,
including jointly virtualized participants. The unary representation and safety
rules below also apply to unary compatibility declarations written with
`contract` and `satisfies`. Explicit participant contracts currently reject
virtual conversion until their joint evidence has a representation.

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

## Consuming resources

`consumes(input)` guarantees that a resource passed by mutable reference is
fully deinitialized on every returning path to which the clause applies.
Inside `on output ..variant`, the guarantee applies only to that variant,
including when the selector follows nested choice payloads. It ends the resource's
previous owned generations, including those nested in fields or choice payloads. The
caller then has an uninitialized place and may assign a new owner to it.
Automatic cleanup does not destroy the consumed value again.

```rg
Releaser: Abstract = (
    release(.self: &Self, .resource: $&Resource) -> ()
        where consumes(resource)
)
```

This is a required post-state, not permission to sometimes destroy the resource.
Each implementation must prove it, including through wrapper calls and early
returns. By-value inputs already transfer ownership of their local value;
`consumes` requires a mutable reference input instead.

Consumption follows the actual caller storage through aliases and structural
fields. Two consumed inputs must designate distinct owners. Ending an owner's
nested resources does not end borrowed external resources or authorize writes
through references stored in its fields. Declare other effects separately.

> [!IMPLEMENTATION]
> Consumption currently requires a known input type. Consuming erased `Self` or
> named domains remains unsupported. Indexed or indirect owners without a lexical
> cleanup identity must first be moved into a lexical owner.

> Ordinary concrete calls can already select cleanup from inferred result
> variants, including when the result is ignored. Whole-input conditional
> destruction without a proven result partition is rejected rather than risking
> duplicate destruction. Selecting a preserving variant establishes availability
> only for the current generation guarded by that call. Copies and moves of the
> result retain the proof; later writes, consumption or independent pending calls
> cannot be undone by selecting an older result. Refinement uses the current
> caller facts and never restores a saved value or storage snapshot.
> Resource refinement remains conservative for conditional hidden retention,
> replacements and conditions requiring several independent discriminants.

```rg
ConditionalReleaser: Abstract = (
    release(.self: &Self, .resource: $&Resource) -> (.result: ?Int32) where {
        on result ..some { consumes(resource) }
        on result ..none {}
    }
)
```

Before selecting the result, the caller cannot use `resource`: it may already
have been destroyed. In `..none`, the resource remains initialized. In `..some`,
it is deinitialized and can receive a new owner. Automatic cleanup follows the
actual result even when the caller ignores it. An empty nested `on` block retains
the consumption guarantees of its enclosing clauses.

## Relocating into available storage

`relocates(destination, source)` guarantees that every returning path moves the
whole source value into the destination. Both inputs are mutable references to
the same value type. The source must be initialized, and the destination must
be available: uninitialized, deinitialized, or already moved from.

```rg
Mover: Abstract = (
    transfer(.self: &Self, .source: $&Resource, .destination: $&Resource) -> ()
        where relocates(destination, source)
)
```

The source becomes moved and the destination becomes initialized. Cleanup follows
the destination, including nested owning fields and active choice payloads.
References to the source's old storage generation expire; transferred owning
roots remain alive. The value retains its existing validity dependencies and
storage capabilities. Relocation grants no new ownership, acquisition receipt,
or extended lifetime to a borrowed resource.

This is a required transition with exact source provenance. Merely initializing
the destination with another value, destroying the source, or moving only on
some returning paths does not satisfy the contract. Source and destination must
resolve to distinct, non-overlapping caller places. Several clauses can describe
independent transfers, but an input cannot participate in multiple transfers or
also be consumed or invalidated by a common clause.

An implementation can use the ordinary `relocate(source, destination)` operation
or a wrapper whose checked summary establishes the same transition. The physical
copy and destination passing remain codegen decisions; they do not weaken the
lifetime obligations.

Inside `on result ..variant`, relocation guarantees apply only to the selected
outcome. The result selects the source and destination availability together;
cleanup follows the actual transition even when the caller discards the result.
A preserving outcome leaves the source initialized and the destination available.

```rg
Mover: Abstract = (
    transfer(.self: &Self, .source: $&Resource, .destination: $&Resource, .move: Bool) -> (.result: ?Int32) where {
        on result ..some { relocates(destination, source) }
        on result ..none {}
    }
)
```

Nested selectors inherit enclosing relocation guarantees. The selected output
may be one of several results; the same rules apply to indirect returns.
Relocations sharing inputs across output discriminants require the corresponding
joint guard and correlated resource and cleanup facts. Proving one selector does
not establish a relocation whose other selectors remain unknown.
Alternative relocations sharing an input must name the same source and
destination; selecting between different ownership destinations requires richer
post-value facts and remains unsupported.

> [!IMPLEMENTATION]
> Relocation clauses require known-type inputs.
> Conditional relocation selects cleanup and refines both known caller
> places from one returned discriminant. Proofs retain both current storage
> generations; overwrites and independent calls cannot replay them. Partial
> replacements and unrepresented effects retain conservative availability.
> Relocation of erased `Self` or mapped storage remains unsupported.
> Indexed owners without lexical cleanup identities must
> first be moved into lexical owners.

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

## Hidden storage contents

`retains(storage, value)` permits a storage input to retain the validity
dependencies and ownership of a by-value input in its hidden contents. It is
an upper bound: an implementation may discard the value instead. Moving the
input into the call already transfers its local ownership; this clause does
not consume another caller-owned place through a reference. It permits neither
fresh acquisitions nor replacement of the storage's generation.
Callers cannot keep live aliases to the precise owned roots of a value that may
enter opaque storage. Declaring retention does not preserve that precise identity.

`from_storage(output, storage, ...)` permits an output to depend on the external
dependencies carried by the named storage inputs' hidden contents. Repeating a
source does not add another dependency. It does not identify a
slot address or borrow the backing allocation itself. Declare `owns(output)`
separately when extraction returns an owner. This is a provenance permission,
not a guarantee that a particular stored value was returned.

Inside `on output ..variant`, `from_storage` applies to the selected payload.
Nested selectors follow that payload's choices. Common sources remain permitted
in every branch; sources declared in one branch do not apply to sibling branches.
For example, a fallible extraction can declare its successful value's provenance
without adding the hidden contents' dependencies to the absent-value outcome:

```rg
Extractor#(.item: Type): Abstract = (
    domain contents

    take(.self: $&Self) -> (.result: ?item) where {
        on result ..some {
            owns(result)
            from_storage(result, self.contents)
        }
        on result ..none {}
    }
)
```

Output provenance does not establish a storage post-state: declare empty-state
or retention obligations separately.

`empties(storage)` guarantees that the storage has no retained hidden
dependencies on every returning path. It does not free the backing storage or
destroy a returned owner. Implementations must destroy or transfer their stored
values before declaring the domain empty. Trusted opaque operations retain
their obligations to maintain occupancy and exactly-once cleanup.

Inside `on output ..variant`, `empties` guarantees discharge only on the selected
outcome. Nested clauses inherit common and enclosing empty-state guarantees.
Until that outcome is selected, the caller retains the storage's possible hidden
dependencies. Copies and moves of the result preserve the proof; overwriting it
removes that proof. A later insertion, replacement of the storage generation or
independent pending call cannot be undone by selecting an older result.

```rg
Drain: Abstract = (
    domain contents

    drain(.self: $&Self) -> (.result: ?Int32) where {
        on result ..some { empties(self.contents) }
        on result ..none {}
    }
)
```

Emptying discharges the storage's dependency obligations, not the dependencies
of a previously extracted value. It neither destroys the backing owner nor
creates or restores a storage generation. Implementations prove the guarantee
on every returning exit of the selected outcome, after normal cleanup.

For example, a single-slot protocol can publish these effects independently of
the implementation's representation:

```rg
SlotProtocol#(.item: Type): Abstract = (
    put(.self: &Self, .storage: $&Allocation, .slot: $&item, .value: item) -> () where {
        retains(storage, value)
    }
    take(.self: &Self, .storage: $&Allocation, .slot: $&item) -> (.value: item) where {
        owns(value)
        from_storage(value, storage)
        empties(storage)
    }
)
```

An extracted owner's external dependencies remain valid obligations after the
storage becomes empty. A borrowing element cannot escape a local referent by
being stored and extracted through a virtual call. Conversely, an extracted
value that does not borrow its backing allocation can survive release of that
allocation. Unrelated storage inputs retain their own hidden dependencies.

`retains` and `empties` require mutable storage references. They cannot both
target the same storage or overlap consumption, relocation or generation
replacement. `from_storage` does not establish the exact reference or ownership
identity promised by `refers_to` or `transfers`.

Storage sources may also name receiver domains. For example, a collection whose
representation stays inside `Self` can declare:

```rg
SlotProtocol#(.item: Type): Abstract = (
    domain contents

    put(.self: $&Self, .value: item) -> ()
        where retains(self.contents, value)
    take(.self: $&Self) -> (.value: item) where {
        owns(value)
        from_storage(value, self.contents)
        empties(self.contents)
    }
)
```

Each implementation maps `contents` to its concrete storage. Calls through a
virtual use that mapped identity; retaining into one domain or emptying it does
not affect another domain. The mapping neither transfers the receiver nor
grants permission to replace or destroy its backing owner. References hidden in
the stored value remain lifetime obligations through erasure, wrappers and
extraction. Returning the collection cannot hide a local referent either.

> [!IMPLEMENTATION]
> These clauses support unconditional effects on known storage inputs and
> mapped receiver domains naming a single storage field, including nested fields.
> `from_storage` supports outcome-selected payloads and nested choices;
> `empties` supports corresponding selected storage guarantees.
> `retains` requires a value input; wrap borrowed references in a value rather
> than using it to move an owner through a reference. Conditional `retains`
> requires correlated ownership transitions and remains rejected. Grouped domain
> mappings require exact hidden transfer identities. Domain mappings crossing
> or selecting reference fields require referent identities and are rejected.
> Naming erased `Self` directly does not name its storage; select a domain.
> Outputs that own storage or contain references conservatively carry possible
> retained input dependencies of local hidden domains without an input identity.
> Extraction preserves those
> dependencies; emptying the returned owner cannot yet discharge this union.

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

Core's `ArgumentSource` illustrates borrowed results: `length` has an empty
contract, while `get` permits its successful `StringView` to depend on `self`
and its error to depend on `error_tracer`. Both native `Arguments` and borrowed
`CliArgumentViews` satisfy this signature. A virtual conversion preserves the
source's dependencies; a wrapper returning `get` cannot outlive locally owned
argument storage merely because the receiver's concrete layout was erased.

Private concrete receiver fields are not fields of the virtual handle. A
returned borrow still depends on the receiver's storage; erasing its layout
must not erase that lifetime dependency. See `34_safety_model.md` for roots,
storage generations, and opaque storage.

> [!IMPLEMENTATION]
> Proving `refers_to` and `transfers` currently requires a concrete body that
> forwards the declared input directly or through a straight-line chain of
> lexical initializers. Every ownership link must explicitly move the whole
> value. Reassignment, additional effects, intermediate calls and control flow
> require more precise storage identity proofs.
> Unconditional input `invalidates` currently supports no-result methods and known
> scalar reference inputs. Conditional clauses also support these inputs and mapped
> receiver domains. Neither
> form permits destroying owners or replacing their hidden dependencies.
> Results containing mapped virtual domains must preserve their identities with
> `transfers` or `refers_to`. A dependency permission alone cannot establish the
> correspondence between a returned handle and its underlying storage.
> Outcome clauses support output dependencies, fresh ownership and conditional
> generation changes. Generation refinement supports bound result discrimination
> and forwarding through stable lexical bindings and direct repackaging. Wrappers
> with rewritten or exposed intermediate results conservatively join effects.
> Conditional hidden retention and grouped opaque domain mappings require
> additional owner identity proofs. Nested payload selectors support dependencies,
> fresh ownership, generation changes and empty-state guarantees.
> Input selectors, nested payload selectors and conjunctions across named inputs
> and outputs support dependency permissions, including permissions on another
> output. Entry-only conditions can select a complete summary before the call.
> Output discrimination narrows payload dependencies after every required
> selector has been established. Generation and hidden-state effects involving
> several independent results remain conservatively joined. Conditional owner
> consumption and relocation require a single output choice; joint declarations
> are rejected rather than publishing incomplete cleanup transitions.

For example, a fixed `Readable#(.item: Int32)` contract can occupy a virtual
handle. Conversion checks the concrete type's declared associated arguments,
then fixes every method signature before erasing `Self`. Handles for different
associated arguments are different types; their possible implementation sets
also remain separate during safety checking.

Nested `on` clauses conjoin structural variant conditions. Repeating the
selected output follows its payload; selecting another named input or output
adds a condition on that value. Input conditions refer to call-entry variants,
so a later mutation or tag test cannot establish the original input condition.
All selectors of a joint guarantee must be proven for the same call.
For an `Errable#(?&Int32, Reasons)` output, an inner `on result ..some`
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

A condition on a named input selects its variant at call entry. An output
condition selects its returned variant. Nesting different selectors requires
both conditions; it does not enumerate combinations of unrelated choices.

```argi
choose(.self: &Self, .mode: Selection, .permission: Permission,
       .left: &Int32, .right: &Int32) -> (.result: &Int32) where {
    on mode ..left {
        on permission ..allow { depends_on(result, left) }
        on permission ..deny { depends_on(result, right) }
    }
    on mode ..right { depends_on(result, right) }
}

split(.self: &Self, .left: &Int32, .right: &Int32) -> (
    .first: Outcome, .second: Outcome, .value: &Int32
) where {
    on first ..yes {
        on second ..yes { depends_on(value, left) }
        on second ..no { depends_on(value, right) }
    }
    on first ..no { depends_on(value, right) }
}
```

For `split`, inspecting `first` alone cannot establish the `left` dependency.
The caller must also inspect `second` from that same call. Copies of those
selectors preserve their call identity; overwrites and selectors from another
call cannot supply missing evidence. Common clauses apply to every selected
alternative, including an empty `on` block.

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

Copies and moves of a call result retain its outcome condition through lexical
bindings. Selecting a field of a multi-output result retains the identity of
that output. A wrapper can forward it through stable lexical bindings while
effects belonging to unselected outputs remain conservative. Selecting one
output does not establish the conditions of another output.
Wrapping that value in another choice retains the condition along its
payload path. Each function exit must establish its own result relation: a return
of a different default or error does not establish a pending call's outcome.
Intervening operations retain their effects, so forwarding an earlier preserving
result never erases a later invalidation or an ordinary content write.

> [!IMPLEMENTATION]
> Concrete dependency inference retains structural choice relations in stable
> terminal selections and straight-line forwarding of one call's exact outputs.
> It does not encode arbitrary numeric predicates or execute bodies symbolically.
> Unsupported operations keep the unconditional approximation. A declaration
> that needs a relation the body cannot prove is rejected with a safety-contract
> diagnostic; it never grants a lifetime merely because the author wrote it.
> Forwarding through intermediate bindings currently requires stable lexical
> initializers and one output assignment on every returning path. Reassigned,
> reference-exposed or loop-produced intermediate values lose provenance
> conservatively. Branch-assigned results and early errors need richer exit
> relations before their conditions can be retained.
