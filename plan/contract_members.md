# Contract members and associated storage projections

Unary region members are implemented; multiple-participant projections remain a
proposal. This is a coherence refactor of contract declarations and conformance
evidence, separate from expanding concurrency safety.
The authority rules remain in [the resource model](resource_authority.md).

## Contract model

A Contract declares named requirements and relations that a selected
implementation must satisfy. It is not an ordinary record or a runtime object.
Keep declaration and implementation syntax uniform:

```argi
.member: Requirement
.member = implementation
```

The requirement determines the member category:

| Category | Declaration | Implementation meaning |
| --- | --- | --- |
| Associated type | `.Result: Type` | Selected compile-time type |
| Associated value | `.capacity: UIntNative` | Selected compile-time value |
| Operation | `.read: (...) -> (...)` | Selected function identity |
| Storage projection | `.state: Region#(T)` | Static projection schema rooted in an instance of participant `T` |

All member names share the contract's declaration namespace; duplicates and wrong
member categories are errors. Preserve existing associated-value restrictions,
operation signature inference, specialization and multiple dispatch. This does
not add new compile-time value representations or runtime function fields.

Contract constraints remain propositions about selected participants and
conformances, not members that an implementation supplies. Operation `where`
clauses retain their safety requirements and guarantees. Providing a storage
projection belongs in the implementation member list, not in an implementation
`where` mapping block. Unrelated constraint syntax is not removed by this change.

## Meaning of Region

`Region#(T)` is a static requirement form, not an ordinary Type, value, function,
allocator or capability token. The initial form identifies one explicit type
participant of the contract. Arbitrary fixed-type or associated-type roots are
not needed for the first migration. Projections depending on several runtime
participants simultaneously are also deferred.

For each selected conformance, a region member supplies a schema:

```text
projection(conformance, member, instance observation) -> storage expression
```

The conformance chooses the schema once; applying it to different instances
selects their respective storage. The schema is not an instance-specific constant
and does not execute a function. Its resulting locations retain their identities,
generations, traversal evidence and possible aliases under the existing rules.

In `.state = region(self.path)`, `self` denotes a symbolic instance root for the
participant named by that member's declaration. It is not a borrowed `&T` value
with fixed readonly permissions. Otherwise a schema selecting an inline field
could never support a mutable operation. Each operation checks the actual
argument's access capabilities when it uses that projection.

The binder exists only inside that region initializer. It neither adds a `self`
argument to operations nor leaks into their lexical assumptions. An operation can
still take `left` and `right`, or have no runtime receiver at all.

`region(...)` is a symbolic construction form in an expected region-member
initializer, not a call to an ordinary function of that name. `Region#(...)` is
classified in the contract-requirement context. These forms need no language-wide
reserved identifiers outside their declaration contexts. Initially accept the
same root-relative paths and grouped mappings as the current domain mechanism:

```argi
.state = region(self.first, self.second)
```

Initializer paths resolve physical fields of the participant: in
`.state = region(self.state)`, the final `state` is the concrete field, not a
recursive lookup of the associated member being defined. Operation safety clauses
resolve associated region names in their contract's scope. Composition does not
merge identically named members from different contracts into one identity.

This groups locations without merging their storage or validity roots. It grants
no read/write authority, ownership, initialization, acquisition or disjointness.
Definition of the schema reads no runtime values; using it may require checked
reads of intermediate references to locate the selected storage. Preserve the
current nonempty grouping, privacy, overlap and traversal checks in the syntax
migration.
Nested selectors require the additional static evidence described below; the
unary syntax migration alone did not enable them.

## Multiple participants

```argi
Comparison#(.Left: Type, .Right: Type): Contract = (
    .left_state: Region#(Left)
    .right_state: Region#(Right)

    .compare: (.left: &Left, .right: &Right) -> (.result: Ordering) where {
        reads(left.left_state)
        reads(right.right_state)
    }
)

implement Comparison#(A, B) (
    .left_state = region(self.first)
    .right_state = region(self.second)
    .compare = compare_ab
)
```

The first initializer binds symbolic `self` to an `A` instance; the second binds
it to a `B` instance. The complete participant tuple selects the conformance
before its associated members are resolved. Regions never rank implementations
or infer participants from a result.

Retain the declaration's participant identity, not merely its substituted type:
`Left` and `Right` can both become `Cell` without making these members or their
schemas interchangeable. Operation inputs bind projections by their declared
participant roles. Several inputs belonging to the same role instantiate the
same schema on their own respective observations.

Different participant roles do not prove different runtime storage. In particular,
two readonly arguments can designate the same object. The proposed general model
checks compatible access and invalidation obligations rather than assuming
disjointness. The current unary domain implementation cannot express all these
cases; enabling multiple-participant regions is a separate semantic extension,
not a prerequisite for changing unary declaration syntax. Existing unary overlap
rejections must not be silently relaxed during the migration.

This does not expand Virtual to multiple hidden participants. Its current unary
restriction remains until joint evidence and instance bindings can be represented.

## Three required scenarios

### A. No abstract storage

```argi
Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type
    .multiply: (.left: &Left, .right: &Right) -> (.result: Result)
)

implement Product#(A, B) (
    .Result: Type = Int32
    .multiply = multiply_ab
)
```

No region or implicit receiver is introduced. Selection and the associated result
retain their existing behavior.

### B. Captured storage

```argi
Counter#(.T: Type): Contract = (
    .state: Region#(T)
    .set: (.self: &T) -> () where writes(self.state)
)

Provider := (._counter: $&Int32)
implement Counter#(Provider) (
    .state = region(self._counter)
    .set = set_counter
)
```

The schema selects the reference's referent, with its locating reads and retained
provenance. A readonly reference to Provider does not prevent using its stored
mutable reference, but the calling execution still needs write authority over the
actual referent. Mapping an inline field instead would require an appropriately
mutable operation input. Changing the member syntax grants neither permission.

### C. Returned references

```argi
Source#(.T: Type): Contract = (
    .storage: Region#(T)
    .get: (.self: &T) -> (.value: &Int32) where {
        reads(self.storage)
        depends_on(value, self.storage)
    }
)

implement Source#(Cell) (
    .storage = region(self.value)
    .get = get_cell
)
```

The same projection supplies an access requirement and a validity dependency.
`depends_on` still does not promise exact target identity, ownership or a binding
for a returned virtual's regions. Existing `refers_to` and `transfers` guarantees
remain distinct; missing result-region relations stay unknown.

## Evidence and implementation boundary

Region members contribute static conformance metadata, not vtable slots or hidden
runtime parameters. Virtual remains a data pointer and a vtable pointer. Applying
a projection binds it to the instance using the existing region and summary facts.
Copies, moves, returns and opaque storage retain or conservatively lose those
facts exactly as before. Retargeting captured references must update or invalidate
the corresponding evidence; renaming the declaration does not solve provenance.

Reuse the current domain descriptors and mapping paths for the initial lowering.
Record each region's member identity and participant root explicitly. Associated
types, values, operations and projections need consistent lookup and validation;
they do not need an identical physical representation or a new runtime system.
Do not encode a projection as a fake ordinary type or callable implementation.

## Remaining validation

Before enabling multiple-participant regions, validate identical concrete
participant types, aliased readonly arguments, incompatible concurrent access,
and projections rooted in the wrong participant. Preserve the declaration's
participant identity through specialization; equal substituted types must not
collapse roles. This needs no new trusted primitive, dynamic descriptor or
ordered-effect representation.

Unary member syntax, receiver-root projections and delegated selectors are
specified in description/135_contracts.md. Their implementation is the baseline
for this remaining work, not a pending migration.

## Remaining delegation integration

Terminal Virtual region selectors are implemented; their language semantics are
documented in description/135_contracts.md. The remaining concurrency work must
use their locating reads and handle observations when bounding Executor
submission, and must independently close native result provenance. Delegation
alone grants no synchronization or thread-transfer guarantee.

Keep factories that may retarget aliased handles conservative until an ordered
provenance representation justifies accepting them. Existing caller-side alias
obligations suffice for independent destination updates; they are not a reason
to introduce an ordered-effect graph now. Multiple-participant regions and
relational guarantees on returned virtuals remain separate design work.
