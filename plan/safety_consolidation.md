# Safety consolidation

Baseline: develop at `fe902869e`. The reference-content integration in the
working tree is a separate candidate. The published unknown-call gate already
checks interference against pending loans before applying completion. The
remaining storage problems can occur entirely in sequential code.

## Evaluation and evidence at ownership boundaries

An ownership-transfer probe at `581e10e4f` uses an owner whose destructor
calls an erased verifier. A call replaces the verifier in the first argument
of a two-argument consumer. When the replacement installs a concurrent
verifier, the compiler rejects the transfer. Swapping the providers makes it
accept an owner whose current verifier is local. Both programs have the same
types and call structure. The second program is a safety regression because
admission uses evidence about the overwritten slot.

The summary evaluator currently splits value inference, local replacements and
capability consumption among different expression walks. The discarded-call
walk recognizes a unary wrapper shape. The capability walk models order and
branching, but its value queries can still evaluate syntax against a later
store. A call should have one evaluation event. Evaluate arguments in source
order and preserve each by-value result and address as evaluated. Observe
call-entry referent contents through those captured addresses after evaluating
the arguments. Instantiate the result and all post-values from that entry
state before committing the post-state. A later evaluation of the same
binding uses the current store.

Apply these rules in both the symbolic and concrete domains:

- Projection of a snapshot reads its represented field. A sparse update
  inherits absent fields from its base. In a complete snapshot, an
  unrepresented field contributes no additional evidence. A stored reference
  supplies an address and lifetime dependency. Dereferencing it observes
  memory through the store at that point.
- Composition collects jointly held facts about one value or state, such
  as the dependencies of two fields of a record. An alternative-state join
  retains every possible dependency, and retains a positive guarantee only
  when it holds in every reachable alternative. Distinguish a missing fact
  from an unreachable predecessor.
- Replacement kills facts about the previous contents of the affected
  projection. Borrow roots, storage identity and destruction obligations
  change only according to their own transitions. Possible writes join the
  replacement with the surviving entry alternatives.
- Substitution interprets a symbolic value in a captured argument environment.
  The environment is local to one call and carries no historical expression
  chain. Preserve sparse updates through substitution when they still have a
  common base.

An owned worker result should use the same symbolic result relation as an
ordinary call. Its transfer obligation is evaluated against the submitted
snapshot and the result relation. The execution receipt authenticates the
result and completion so extraction can reissue ownership with fresh
generations. The result relation must account for replaced fields and each
reachable normal return. An unknown relation cannot justify retaining
caller-side metadata. Exact moves are the empty-update case of this model.

Use paired replacement tests in both directions, including nested calls,
discarded results, and conditional evaluation. Include a case where a later
argument mutates a slot whose old value was captured by an earlier argument.
Compare the same owner transformed by an ordinary call and by a worker.
Measure full-suite results and compare frontend time, peak memory, output
size and specialization counts with the same fixtures and build settings.

## Exclusive lending of a work queue

An exclusive loan of a nonplain String already works through an erased
interface and certified completion in fixture `433_owned_task_string`.
The same shape with a `RingBuffer#(UInt8)` filled with two items and a
worker removing the first item fails at the interface boundary. The
following contract covers the receiver's structural storage:

```argi
Work#(.R: Type): Contract = (
    .take: (.queue: R) -> (.item: UInt8) where { writes(queue) isolated() }
)
implement Work#($&RingBuffer#(UInt8)) (
    .take = (.queue: $&RingBuffer#(UInt8)) -> (.item: UInt8) {
        item = unwrap_or_abort(pop(.self = queue))
    }
)
```

With a local queue and an ordinary mutable receiver, constructing
`Virtual#(Work)($&queue)` reports that `take` exceeds its declared bounds.
The ordinary queue operations compile in the same program. Removing an
element accesses queue-controlled backing in addition to its structural
fields. This probe separates the interface's ability to name that backing
from the execution's ability to lend the queue exclusively.

Moving that implementation into the queue's owner module gives access to
its private fields. Declaring a named region mapped to
`region(self._allocation)` and adding `writes(self.storage)` still exceeds
the declared bounds. Mapping `region(self._allocation._storage_reference)`
also fails. These paths identify a structural allocation slot or an
optional reference slot. The access effect refers to the owned backing
selected by the allocation, so the mapping needs a way to denote that
existing storage identity.

A positive probe should read the second item after completion without
synchronization. A negative probe should reject access to the same backing
before completion, including access through an independently obtained view.

## Backing alternatives after growth

On the compiler at `0d4855875`, take a view of a String after calling
`ensure_capacity_growing` on one branch, or after a loop that may grow it.
Both new views are rejected when used. The diagnostic reports an ended
root. An old view taken before an unconditional growth is also rejected,
as required. These probes call the growth operation explicitly, so
formatting into reserved capacity cannot hide the join limitation.

The store join needs a proof about the current owned backing on every
incoming path. It may then issue a current observation tied to that
storage. It cannot treat all historical backing roots as live. Old views
must keep their original dependencies, and active loans must continue
to conflict with access to their backing. The loop join already has
machinery to stabilize owned roots of a slot. A general join should share
the proof of ownership and observation, with the loop separately bounding
how many generations survive fixed-point iteration.

A control at `0d644383b` removes the historical view entirely. A fresh
view still fails after conditional growth, while unconditional growth and
omitting growth both compile and run. The join therefore loses the proof
that the current backing is live even when no old view is retained. The
unconditional-growth stale-view control remains independently necessary.

The [conditional owner replacement](examples/conditional_owned_backing/main.rg)
reproducer narrows this failure to a single ordinary branch. Each predecessor
leaves an initialized array with one backing. The new iterator after the join
is rejected. Adding `else { return }` leaves only the replacement predecessor
and the same iterator compiles and runs. The existing collection fixture 29X
still rejects an element reference retained across unconditional growth.

The failed iterator originally carried three maybe-live generations in the
reduced program. One belonged to a lexical field observed on only one
predecessor. The slot was initialized on both paths, but the join had retained
the older generation entry without marking it for renewal. Renewing the
lexical observation on demand removes that generation from the failure. The
two remaining generations identify different heap backings and still need a
proof relating each backing to the owner on its incoming path.

The incoming array facts each have one live owned root at the same structural
allocation field. The concrete reference leaf has no intrinsic backing marker
in either predecessor. Instead, summary instantiation reads the backing through
an input-owned-roots recipe. That recipe currently flattens owned roots into
ordinary validity dependencies. A proof based only on explicit reference
markers would miss this path. The same rejection occurs with a C allocator in
place of the page allocator.

Collection fixture 178X uses the same branch structure and reads a reference
obtained before the replacement. It must continue to reject when the new
iterator in the reduced program is accepted. Both cases exercise the same
conditional retirement, with the observation taken on opposite sides of it.

Retirement includes guarded outcomes before the outcome is selected. An
observation that sees only unconditional retirements could survive a call
that may free the selected backing. `Tracker.end` and
`Tracker.deferRetirement` cover the concrete retirement transitions. A
control-flow join combines their effects. The loop fixed point will need to
compare the surviving observations and their obligations, since requiring
fresh event numbers to repeat would prevent convergence.

The checker now records the latest possible retirement in the shared proof
namespace. For a root owned and live on one predecessor and absent from the
other value, a dependency on the current owner records the joined mark. The
input-owned-roots summary recipe copies that dependency into a new observation.
Ordinary aliases retain their original dependencies. Collection fixtures 178X
and 179 exercise this contrast. The mechanism also recovers the geometric
growth and priority queue fixtures. At subsequent joins, an incoming owner
can use its still-valid witness in place of unconditional root liveness.
Every incoming value must either prove its owned observation or omit that
root entirely. This lets word count retain its current backing in the loop
without changing what any physical root denotes.

The retirement mark certifies access through an observation. It is not a
precondition for carrying conditional cleanup custody in the owning value.
Checking the mark before the existing custody rules rejected fallible map
copies while forwarding their partially constructed owners. Access through
an independent alias still requires current lifetime evidence.

Prove the relationship between a current observation and its backing on each
incoming path before joining the evidence. Merged owner-root membership alone
is insufficient, since a joined value can retain roots from multiple paths
or from historical observations. Resulting observations must retain every
possible retirement and overlap obligation. Apply the same rule at loop
headers, with a bounded representation for renewed generations. Use the
single-branch reproducer and the stale-view control before evaluating the
larger word count, CSV and URI consumers. Investigate the geometry kernel
diagnostics independently until their backing relationship has been traced.

### Lending a reference selected at a join

A helper selecting between two ordinary mutable references to distinct
scalars can return a reference whose alternatives are both valid. A probe
passes that result to a worker that writes through it and reads the chosen
scalar after awaiting completion. The baseline checker rejects submission
because the merged reference has no authenticated target. A direct local
conditional assignment with the same two alternatives produces the same
rejection. Passing the same scalar as both alternatives through the helper
compiles and runs, including the worker write and the read after completion.
The retained
`mutation_places` can weaken facts about possible destinations, but give
no evidence of complete coverage of the accessed extent.

The useful guarantee here is complete coverage by authenticated regions.
An execution loan would suspend incompatible authority over every covered
region until its receipt completes. An unknown or widened alternative
must break the coverage guarantee. Compare this against existing offset and
reinterpretation negatives before letting a mutation candidate contribute to
the proof. This uses the same distinction as a join of owned backing:
collective membership may survive even when an exact identity is lost.

Execution admission now recognizes complete coverage of a reference selected
through a control-flow join or instantiated from an ordinary summary.
Each covered destination receives a loan with the same completion receipt.
Fixtures 443 and 444X exercise disjoint access and conflicting access before
completion. Fixture 445X joins a direct reference with an unbounded offset
and checks that the uncovered alternative prevents admission.

## Branch snapshot cost

In a synthetic function, each branch assigns a scalar accumulator and adds
one binding to the surrounding scope. Three runs per case used a ReleaseSafe
compiler, a cold frontend and one frontend worker. The previous
implementation copied effects by value into each binding map snapshot.
Sharing immutable payloads between snapshots gives these medians:

| Branches | Safety before | Safety after | Peak RSS before | Peak RSS after |
| ---: | ---: | ---: | ---: | ---: |
| 32 | 5.4 ms | 2.0 ms | 112 MiB | 111 MiB |
| 128 | 63.7 ms | 16.9 ms | 166 MiB | 114 MiB |
| 512 | 930.0 ms | 211.7 ms | 1,093 MiB | 154 MiB |

A branch still walks the live binding map at the join. The remaining growth
in time warrants a benchmark that isolates revisiting unchanged bindings.

For ordinary summary composition, a separate probe passes one owned String
through a chain of functions with the same forwarding signature, then
submits it to a worker and reads the returned byte. All three binaries ran
successfully. Three cold ReleaseSafe runs with one frontend worker gave:

| Forwarders | Summary evaluations | Summary bytes requested | Safety median | Peak RSS median |
| ---: | ---: | ---: | ---: | ---: |
| 16 | 215 | 29,628,061 | 29.3 ms | 121 MiB |
| 64 | 311 | 48,968,085 | 46.9 ms | 125 MiB |
| 256 | 695 | 126,110,349 | 120.1 ms | 136 MiB |

Each added function accounts for two more summary evaluations and about
403 kB of cumulative requests. The request count measures all allocations
during inference, including scratch storage. The result bounds the cost
observed for a forwarding chain, where each function exposes one relation.
It leaves cycles, branching wrappers and opaque collections unmeasured.

## Extracting a transferable owner from opaque storage

An extraction probe uses `DynamicArray#(String)`, inserts an owned String
with `push_assume_capacity`, and takes it out with `pop` through an ordinary
forwarding function. Allocate the array before sharing the provider so the
array's allocation effects do not obscure the extraction.

| Inserted values | Operation after extraction | Observed result |
| --- | --- | --- |
| One String with a local deallocator | Read its byte and destroy it locally | Compiles and runs |
| One String with a concurrent deallocator | Read its byte while the provider is shared | Rejects because the reference target is not proved independent of shared storage |
| One String with a concurrent deallocator | Transfer to a worker and await the returned owner | Rejects for missing transfer evidence |
| One local and one concurrent String | Transfer the extracted value | Rejects for missing transfer evidence |

The extraction primitive issues fresh cleanup custody and retains external
dependencies from opaque storage. It cannot reconstruct the erased release
capability or the relationship between the extracted address and its
backing. Insertion must establish those guarantees collectively if extraction
is to recover them. The collective guarantee cannot discharge the retained
lifetime and access obligations, and successful extraction must still
transfer cleanup custody for exactly one element.

## Acceptance criterion for storage summaries

A summary describes a relation between entry and exit stores. For every
concrete entry represented at a call site, instantiating the summary must
include every exit the body could produce with those actual arguments.
Check this separately on each published return outcome. This criterion also
applies when several formal paths resolve to one cell.

Consider a helper that writes a replacement through either its first or its
second argument on every normal return. With different actual cells each can
retain its old contents. With the same stable actual cell its old contents
are gone on every return. Recording two optional writes is sound for both
calls, but cannot establish the repair in the second call. Recording two
definite writes is unsound for the first. A sufficient summary for this
example is one unconditional whole-cell replacement with a choice of
destinations. Substitute the evaluated arguments into the choice before
testing whether every alternative covers the observed cell. An uncovered
alternative prevents that proof. If payloads differ by branch, retain their
association with the destination or widen to all possible payloads.

Use this as a differential test for the body visitor and summary consumer.
Compare an inline branch, one helper and a forwarding helper, with equal,
distinct and uncertain actual destinations. Check both the repaired read and
a read that could still observe the old dependency. Re-evaluating a selector
at the next call supplies a new choice unless stability is proved. Loops can
forget the correlation while retaining every potential dependency. This test
justifies preserving a bounded destination choice where a repair needs it.
It does not require retaining arbitrary branch predicates or call histories.

A definite replacement discharges facts specifically about the previous
contents of the covered slot. Ownership disposal still requires its cleanup
transition, and reclaim still requires publication for the exact execution.
Replacing a slot that carries a receipt cannot certify completion.

### Conditional repair at a call boundary

Compile-only probe on the local integration compiler, 22 November 2026.
Start with two slots holding a live reference. Store a temporary reference in
the first slot and let the temporary expire. The repair helper is:

```argi
repair := (.a: $&Slot, .b: $&Slot, .replacement: &Int32, .choose: Bool) -> () {
    if choose { a&.reference = replacement } else { b&.reference = replacement }
}
```

Read the first slot's referent after the following operations, with a live
replacement and a Boolean parameter in the enclosing function:

| Operation | Required | Observed |
| --- | --- | --- |
| Both inline branches assign the replacement to the first slot | Accept | Accept |
| Call `repair` with the first slot twice | Accept | Reject at the read |
| Forward both arguments unchanged to `repair` from another helper, passing the first slot twice | Accept | Reject at the read |
| Call `repair` with distinct slots | Reject | Reject at the read |

The distinct-slot result checks the branch that leaves the expired reference
in place. The same-slot results isolate loss of a repair proof across a call.
All three diagnostics report an ended root. Any implementation that removes
that diagnostic for the same-slot call must retain it for distinct slots.

## Diagnosis

| Mechanism | What it represents | Where coherence can fail |
| --- | --- | --- |
| Place, symbolic pointee, captured route | Different descriptions of storage | Two descriptions may denote one cell. Distinct symbolic names prove no separation. Typed overlap must include union alternatives. |
| Validity root and generation | Lifetime dependency and incarnation | A generation can end while a reference remains stored. A shared lifetime says nothing about physical overlap. |
| Place and symbolic value tables, observed writes | Baseline content and reaching updates | A raw table lookup can bypass a write recorded under another spelling. |
| Opaque storage | Bounds on what a container retains | A bound on retained lifetimes may be sufficient for a validity check and insufficient to locate a mutation. |
| InputPath, InputRoute, ValueEffect | Caller-relative recipes | A route that locates a cell at the point of observation may resolve differently at call entry. A dependency may survive when its write destination cannot be expressed. |
| Execution state and receipts | Outstanding loans and authenticated transitions | Clearing one receipt must leave incompatible outstanding loans in force. |
| Ownership and cleanup | Responsibility plus requirements of eventual destruction | Moving an owner cannot turn a borrowed cleanup provider into owned or globally accessible storage. |

The split between lexical and symbolic representation is useful. The split
between a baseline content read and an alias-aware content read is accidental
at a semantic use site. In the candidate, `reconstructPlaceValue` refreshes
structural descendants while `readReferenceCell` overlays reaching writes.
`loadSummaryPlaceValue` and `readEvaluatedAccess` mediate some reads. Other
consumers look up values while resolving paths or captures. Each consumer must
say whether it observes current contents, an already evaluated snapshot, or
only an address. Bulk substitution of one lookup for another would conflate
these and can undo tested behavior.

The three historical counterexamples concern temporal safety inherited from
0.4: a write reaches an uncovered alternative, an effect stops at a function
boundary, and two evaluations are mistaken for the same observed reference.
0.5 adds a second consequence of stale content: a stale referent can authorize
the wrong region during a loan. Race prevention and memory publication are
additional obligations, with their own native assumptions.

## Concrete state and transitions

### Evidence boundaries and shared operations

The checker already stores separate facts for storage, lifetime, authority,
and cleanup. Its operations do not enforce that separation. For example,
`ValidityDependency` stores a root and retirement mark, but the same root ID
also appears in `owned_roots`, opaque provenance, and execution loans.
`collectDependencyRoots` can therefore feed a lifetime reconstruction even
though it intentionally discards the mark. The native and symbolic domains
also each implement their own aggregate projection and alternative join.

Keep the existing facts and make their operations explicit:

| Question | Evidence consumed | Result of losing precision |
| --- | --- | --- |
| Which storage could this operation touch? | Typed place or symbolic route, with completeness | Retain all known alternatives and an unresolved footprint |
| Is this observation still valid? | Generation and the observation's retirement evidence | Require unconditional liveness when conditional proof is lost |
| Is this execution allowed to access it? | Mode and covered region checked against outstanding loans and shared authority | Keep possible conflicts until a certified completion |
| Who must destroy this value? | Selected owner slot or authenticated custody transition, plus latent cleanup requirements | Retain every possible cleanup obligation |

Give lifetime transport a typed interface over `ValidityDependency` and
confine root-only collection to identity queries such as overlap, retirement,
and retention. Form a bare dependency only at a new observation, or at an
explicit loss of proof with conservative semantics. Apply the same boundary
to opaque storage: its retention record may use identity for retirement
checks, but publishing an observation needs a retained witness or an explicit
loss of proof. Owner membership can justify a custody operation and cannot
repair an independently captured alias.

Opaque capture and extraction now traverse the same structural values and
preserve distinct retirement witnesses even when they name the same root.
Retention projects those witnesses to identities at the destination. Inferred
opaque provenance already has an observation at that node, so collection can
skip the scan of tracked storage and inspect only explicit provenance for
additional generations. A provenance-only generation contributes a bare
dependency, which requires unconditional liveness.

Use the existing structural facts to share projection and collection rules.
Separate combining facts from one value from joining alternative values.
Combine retains obligations from both operands. Join unions obligations and
keeps a positive guarantee only with a proof on every relevant predecessor.
Projection selects an explicit child, a completely covered alternative set,
or an unresolved selection. Each outcome should drive every evidence domain
through the same traversal. Concrete values and summary recipes can retain
their own leaves without duplicating these structural decisions.

#### Summaries and loop convergence

In a summary, distinguish the recipe that selects a value from the evidence
requested from it. Reuse `InputPath`, `InputRoute`, and capture phases to
select an evaluated argument, an entry observation, or checked post-state
contents. Apply the requested access, lifetime, or custody operation to
that selection. Rebase fresh callee identities before substituting caller
evidence. Cache only caller-relative recipes. A summary must never infer
authority or custody solely from a dependency that survived substitution.

The loop header must denote every permitted state at the next test.
Use one abstraction for initial entry and repeated edges. Compute
the body, continue transfers, increment, and next condition from that
header. Accept only when the entry and abstract backedge are included
in the header. Accumulate breaks separately and check the exit against
the header and all break states. A work limit can reject an unproved
loop but cannot establish inclusion.

Represent storage sites and value observations separately. An entry
identity remains exact. A repeated producer gets a bounded key from
its site and the role selected by its checked summary, with a current
instance and a summary of older instances. Reusing a key for a new
current instance demotes the previous one everywhere it can be
observed. This is a simultaneous state operation, including stored
values, projected storage, opaque provenance, pending receipts and
completed outputs. Demotion never updates a historical borrow to the
new instance. A joined current instance can authorize a strong
operation only where every alternative identifies the same role and
carries the required authority. A summary instance supports weak
updates and possible conflicts until stronger evidence is available.

Key embedded symbolic storage by the parent storage role and selector.
Track its parent observation separately. A projection observed through
an ended parent remains historical even if another observation selects
the same field. Lift only the current projected initializedness and
contents into a joined current role, and preserve writes through
possible aliases in the weak store. Use typed wildcard indices and
finite caller-relative projection paths. If traversal loses a finite
path, retain an unresolved footprint and its lifetime and custody
requirements.

Opaque domains keep may-retained dependencies per role and observation.
Emptying a current domain can clear only that instance's contents.
Overlapping historical domains retain the union of their requirements.
Pending receipts remain distinct from observation and ownership
identities. A join preserves possible pending authority restrictions
and takes the common proof of completion. Custody can authorize
destruction only with a definite current owner. Historical alternatives
keep possible cleanup and retention obligations.

Build the representation around ordered, immutable facts and compare
the complete state relation. In particular, identity renaming alone
does not equate a current singleton with a summary of older instances.
Start by assigning bounded roles to embedded symbolic projections and
their opaque contents together. Check transfer inclusion for a refresh
with a retained historical alias, a pending loan, and opaque contents
before enabling the representation for general function bodies.
Reuse the entry-relative site and role keys when substituting summaries,
so a summary does not publish solver-local IDs.

The concrete loop driver requires equality of consecutive headers.
Exhausting its work budget rejects an unsettled header. The strict
Debug loop run passed 33 fixtures and failed 14. The failures include
valid array growth and iterator loops, and negative fixtures that stop
before their intended diagnostic. Use these as precision requirements
for the bounded abstraction above.

At c0a21ec3c an instrumented Debug run with one frontend worker
distinguished two forms of growth. In fixture 259, tracker slots rose
from 38 to 87 across eight transfers while the twelve symbolic rows
and ten lexical places stayed fixed. No symbolic contents or opaque
rows were present at that header. For fixture 183 the eighth header
retained 118 tracker slots, 51 symbolic rows, 25 stored symbolic
values and eight opaque rows. The last edge still added six symbolic
rows, three stored values and an opaque row. Stable embedded backing
reduces generation allocation but does not itself bound observed
storage or its retained contents. Use fixture 259 to measure
observation-only normalization and fixture 183 to measure the
simultaneous storage and observation transfer.

At ea2f7e31e the Debug loop filter passed 40 fixtures and failed
seven. The owner join recovered passing growth and fresh-observation
cases and the expected stale-alias diagnostic. The remaining failures
include both mixed propagation probes, symbolic DynamicArray growth,
lexical escapes and the two text growth controls.

Compare checker
time, peak memory, abstract loop iterations, and retained facts on the same
input while scaling the number of owners, loan receipts, and wrapper calls.
Use the existing stale-alias, opaque-retention, and disjoint-loan controls
alongside growth loops. Add a loop whose observable effect needs more than
eight steps to propagate before replacing the cutoff.

The concrete loop driver evaluates the condition on entry and on each
backedge. Fallthrough and continue feed the increment and then the
condition. Break contributes to the exit without re-evaluating either.
The pending-loan check examines the state after these backedge effects.
Each abstract transfer contributes break states to an exit accumulator.
Its observations stay out of the header and constrain generation-name
reuse while the solver advances. This preserves effects seen on earlier
exits when a later header has widened its observations.

Execution-state equality compares loans, output custody, and retained
access evidence in receipt order. A consumed result can still carry
evidence used to check effects through the receipt. A pending receipt
with no attached output can still accept custody, unlike one whose
output has already been reserved. Completed entries with neither
custody nor evidence are irrelevant to this comparison.
Fixture 417X exercises a condition that observes an old alias after a
continue, even though the resource slot has already been reinitialized.

Input post-state inference uses the same edge order. It joins continue
with fallthrough before executing the increment and the next condition.
Break effects contribute to the exit without producing an observation
on a later iteration. Fixtures 142X and 286 exercise the same aliased
call with repeated execution and with a break, respectively. The summary
still approximates repeated effects from one abstract backedge.

Storage capability summaries share that separation of loop transfers.
Only effects that reach another iteration contribute to repetition
bounds. Continue paths run the increment before counts widen. A
capability consumed exclusively on a break contributes to the loop exit
with its finite count, as fixture 419 verifies.

The capability transfer now replays calls first evaluated by the loop
condition after the backedge updates its arguments. Call deduplication
still applies within each evaluation. In fixture 422X the entry test
uses a local allocation, while the body retargets the argument to a
caller-owned acquisition. The repeated test must publish the effect
on that caller input.

Fixture 423X delays this retargeting by another iteration. Capability
inference now joins the entry with the backedge until bindings, address
alternatives, counts, and conflicts stabilize. Counts saturate at two.
Break and return states accumulate separately and do not contribute to
repetition. The work limit rejects an unsettled capability summary
instead of publishing a partial transfer.

A concrete probe uses two lexical resources and twelve reference slots
initialized to the first resource. Each iteration copies the references
from high indices to low indices in assignment order (slot 11 receives
slot 10 first) and then assigns a reference to the second resource to slot
0. After twelve iterations, destroying the second resource and
dereferencing slot 11 is accepted by the current checker. A four-step
version is rejected at the final dereference. A twelve-step control that
only assigns references to the first resource compiles. The long probe
uses fixed identities with no acquisitions or allocation in the loop, so
it isolates propagation depth from generation widening.

The positive scaling control retains both resources and reads the tail.
With the eight-iteration cutoff, medians of three ReleaseSafe builds
with one frontend worker and the frontend cache disabled were 1.29,
1.54, 2.23, and 7.88 ms in GlobalSafety for 4, 12, 32, and 128 slots.
These timings are a baseline for the incomplete solver. Future
comparisons must record the number of abstract iterations alongside time.

A diagnostic experiment raised the limit to 256 and rejected any loop
without structural equality at that limit. The loop suite returned 27
passes and 11 failures, including positive iterator, ownership, and text
cases. A second run traced three representative cases with a 24-step
limit. The long reference-chain probe stabilized at iteration 12
(zero-based) and then reported the stale dereference. By contrast:

| Fixture | Tracked roots at the ninth transition | Places before and after | Continued growth |
| --- | ---: | ---: | --- |
| 12 iterator loops | 28 to 30 | 8 to 8 | Two roots per transition |
| 261 fresh alias | 86 to 93 | 11 to 11 | Seven roots per transition and a reused owner alternates between live and dead |
| 268X local escape through continue | 12 to 13 | 4 to 4 | One root per transition |

The convergence comparison needs to quotient generation names while
preserving their relationships to live observations and obligations.
The iterator and local-escape cases provide controls for historical
generations. The fresh-alias case additionally requires retaining the
relationship between current ownership and its valid observations
across the backedge. Re-run these cases before testing a larger budget
or applying the resulting solver to summary state.

The loop root inventory now uses one traversal to find the retained
prefix of the tracker. It includes guarded snapshots, retained execution
outputs, pending loans, opaque records, and canonical roots in the loop
context. Ended lexical classifications follow their referenced roots.
The same traversal supports point queries when deciding whether an
existing root can be reused. Trimming discards an unreferenced suffix
without reusing its identities or merging any observations.

Exact loop state equality includes retirement marks on all present
roots. A non-owning root can carry a conditional validity witness just
as an owned root can. An exact comparison therefore cannot use ownership
as a proxy for observation validity. When a proven unretained symbolic
identity is reused as a canonical name, it receives the current
generation's metadata. A root substitution leaves marked observations
attached to their original retirement evidence.

The concrete driver allows propagation to continue past eight
transitions when the loop has allocated no validity, symbolic, storage
capability, or execution identity. The entry place count supplies a
work budget, while exact state equality provides the convergence check.
Exhausting that budget reports non-convergence. This closes the
twelve-slot stale-reference case (fixture 418X). Loops that mint
identities within the original budget still use the prior approximation
and need a sound generalization of generation widening.

A repeated DynamicArray push through a mutable input exposed another
constraint on symbolic generation reuse. In the reduced bridge trace,
the backing root 0 remains live. The push summary ends observation 1
and renews the argument to 23. Joining with loop entry issues observation
28, and the next join issues 47. Widening 47 back to 28 also makes
the projected-storage cache find children interned under the previous
incarnation of 28. Their uncertain initializedness prevents the next
possible replacement from renewing its argument. The backedge then has
an ended observation 28, and the join retains both stale alternatives
instead of creating a current generation.

Keep generations that have named projections out of this reuse path.
Reusing those identities efficiently requires transporting the current
projected facts and separating them from historical child observations.
The existing generation budget still bounds this case. Collection
fixture 183 runs both growth and reserved-capacity loops. Fixture 184X
requires rejection at the historical view read after the loop.

The [mixed-generation propagation fixture](../tests/feature_tests/ownership/420X_loop_push_propagates_retired_reference/main.rg)
extends fixture 418X with an independent DynamicArray push on the backedge.
At 529374bc0 the probe compiles even though the twelfth slot can hold
the retired reference. The reserve of twelve elements rules out runtime
allocation as the cause. Abstract push still creates a new observation,
triggering the eight-transition cutoff and stopping propagation of the
unrelated reference chain. The original 418X still rejects the final
read. Reading the fourth slot in the mixed probe still yields the
expected diagnostic. Keeping the twelfth-slot read and assigning only
the live reference to the first slot compiles. A generation budget must
never terminate propagation of a separate changing store fact.

The former generation cutoff waited for the lexical slots' dependencies on
entry roots to stabilize. Fixture 420X requires the diagnostic at the
twelfth-slot read. The check compares entry root identity and
whether each witness remains valid in its own predecessor. The raw
retirement mark can change even when a renewed observation remains
valid, as in the UTF-8 copy-after-continue fixture. This gate addresses
the demonstrated propagation loss. Changes confined to new roots,
symbolic stores or opaque domains still need a checked widening.

Fixture 421X replaces the old owner on each iteration before taking
its address. Its relevant observation is born inside the loop. The
cutoff also checked concrete reference targets and sets of possible
mutation destinations in lexical slots. These identities stay comparable
as generations change. The fixture requires rejection at the final
dereference. A change of observation through the same destination still
requires a checked widening of the generation relation.

In a Debug experiment, requiring exact equality at the existing work
budget rejected both the valid growth control and the mixed probe for
non-convergence. In each control every backedge added 19 tracker slots,
six symbolic pointee rows, three stored symbolic values after the first
join, and one opaque domain. The lexical place count stayed fixed and
the reference-write table stayed empty. The mixed probe still added
the same rows on its twentieth transition. Trimming only the root array
cannot make these states converge. The widening has to cover symbolic
projections, their contents, and the opaque domain together, while
checking propagation of the unaffected lexical slots independently.
The straight-line control compiled with the same diagnostic build.

The ReleaseSafe geometry kernel at 529374bc0 compiled and ran with
one frontend worker and the frontend cache disabled. The build took
2m28s and reached 2,185,996 KiB peak RSS. The earlier ReleaseSafe
reference stopped in Safety at the bridge diagnostic, so its peak
does not measure the cost of reaching code generation.

Three alternating Debug builds per revision, with one frontend worker
and the frontend cache disabled, measured the fixed-identity controls:

| Slots | Old GlobalSafety median, ms | New GlobalSafety median, ms |
| ---: | ---: | ---: |
| 4 | 6.76 | 6.82 |
| 12 | 7.56 | 7.81 |
| 32 | 10.60 | 15.97 |
| 128 | 31.50 | 252.15 |

At 128 slots the checker cloned state 136 times. Whole-state rescans
are expensive when information advances one slot per iteration. This
control measures the cost of removing the propagation cutoff and
provides a baseline for dependency-directed updates.

Joins and equality checks now use the existing entry order to match
storage in constant time when both predecessors retained that order.
When entries have diverged, matching falls back to the full place
identity, including projections. Ownership widening skips exact pairs
with no owner roots. Three alternating Debug builds of the same
128-slot control measured a GlobalSafety median of 275.35 ms before
and 215.06 ms after this change. The loop still evaluates each
iteration needed for convergence.

Model a cell by physical allocation and extent, with a separate incarnation
and initialization state. A reference value carries an access path and
observed lifetime dependencies. The concrete store can retain an old
reference after its incarnation ends. Dereferencing it requires a live
incarnation, initialized representation, physical containment, and authority.
Copying its bits neither reads the referent nor grants authority. Escaping a
borrow and invoking cleanup remain subject to their own obligations.

Track responsibility once per owned resource. Its cleanup is an operation
with a footprint, execution requirements, and dependencies. Model ordinary
authority as grants in custody of an execution or protocol, restricted by
outstanding loans. A read loan leaves compatible readers, a write loan
suspends incompatible access. Reclaim removes exactly the loan whose
completion is certified. Submission failure may restore custody only if
there was no admission that could permit access. Otherwise cleanup must
establish completion and publication. Owner transfer changes responsibility
and the required grants permanently. It does not reclaim the owner at join.

Protection deposits authority in protocol custody. An acquisition lets one
execution use that authority through an acquisition-scoped observation.
Release ends that observation and returns custody, subject to any derived
loans. Reacquisition cannot validate refs from an earlier acquisition.
A preexisting alias cannot use protected storage outside a valid acquisition.
Native synchronization must establish publication on handoff. These are
semantic transitions to validate before choosing additional checker data.

## Abstract storage interface

Use one meaning of load, store, and forget across typed Places, symbolic
cells, and opaque domains.

- Load a value from all possible current cells and include all reaching
  writes. Where contents are hidden, return only a conservative interface
  bound. An evaluated snapshot retains the facts of its evaluation.
- Store strongly only with a definite write to the same stable observation
  and enough coverage to replace the relevant extent. Store weakly to every
  represented candidate otherwise. With incomplete coverage, retain the
  unresolved effect as well. Repair of one candidate cannot erase it.
- Forget precise identity by widening destinations and weakening overwrite
  proofs. Retain retained lifetimes, cleanup, and execution obligations.
  Never use an unknown destination as an empty footprint.
- A repeated producer may create a fresh observation. Widen former
  incarnations into weak summaries at iteration boundaries. A copy of an
  evaluated reference can retain its observation while the underlying
  storage generation is live. The finite domain tracks bounded current
  observations and widened effects, with no unbounded event history.

The abstraction obligation is successor inclusion: for every concrete state
represented at entry, every concrete successor must be represented after the
abstract transition. Two candidate lists with different completeness can
carry the same dependencies. The failed experiment filtering generic source
paths caused lost FFI and execution obligations, so completeness must be
consumed by an explicit destination query independently of dependency
substitution.

### Loop header domain

Use a bounded recency abstraction for each abstract storage or producer
partition. Keep entry-relative identities rigid. Name a projection by
its base partition and typed path, with an unresolved suffix once the
statically distinguished path ends. Partition fresh production by the
operation or summary output role and its abstract destination. Repeated
traversal and recursive summary substitution must reuse these partitions.
Overlapping partitions denote possible aliases, including distinct
entry-relative paths and overlapping union alternatives.

Each partition can distinguish a current singleton from a summary of
prior or non-singleton instances. Producing a new singleton ages the
previous singleton into the summary in one simultaneous substitution.
Apply that substitution to reference payloads, reaching writes,
projection keys, hidden contents, owner associations, choice evidence,
authority grants and execution receipts. A location whose base was aged
also loses its strong-update proof. A previously invalid observation
remains invalid after aging. An observation of a potentially live older
instance carries possible liveness and possible authority separately.
Neither possibility suffices to authorize a use.

The summary component represents multiplicity. Joining two cleanup
obligations into the same partition must retain the possibility of
multiple owners. A store, release, completion or cleanup may remove an
obligation from the summary component only with proof that it applies to
every represented instance. Otherwise the operation retains the possible
outstanding obligations. Opaque contents use the same representation for
contained observations and owner associations. Unknown traversal loses
precision in the target and retains possible hidden effects.

The tracker distinguishes singleton roots from roots representing
multiple instances. A history root cannot establish a current
observation, be revived by an outcome, or establish a transferred
owner. Retiring one member preserves possible liveness of the others
and does not advance a history-specific retirement counter. The
expired lexical observation summary already uses this representation.
Fresh summary roots carry an interned producer keyed by the call site
and the summary's fresh effect source. Repeated evaluations establish
distinct root identities carrying the same producer. A checked custody
transfer preserves that producer when it reissues the root. The loop
header currently uses the partition for expired resource observations
whose roots have no other retained obligations.

At loop headers, an embedded reference write whose parent generation
has ended can move to the history of its stable backing. This requires
the old observation to be unreachable from values, opaque storage,
loans, entry and exits. The history retains all reaching payloads and
discards exact overwrite proofs about the aged observation. Other
symbolic cells can still alias the write. The history key cannot be
used as a current storage observation.

In the reduced bridge trace, the destination's symbolic identity 0
keeps backing 0 while the first two joined observations are 26 and 39.
The second transition creates six more projected identities and an
opaque row. The field-zero projections keep backing 10. Before
generation-checked inheritance, the old opaque row for projection 7
also picks up owner 29 from the joined aggregate, even though it was
recorded under observation 23. The row now retains owners seen under
its own observation in either predecessor, along with its recorded
associations. The growing set of possible owners in the current
aggregate still needs a multiplicity abstraction.

A subsequent instrumented Debug build at `6aef84f2d` confirmed that the
first transfer adds six materialized symbolic rows and each later transfer
adds four. Each adds one opaque row. The newly added opaque rows have
neither hidden dependencies nor a guard. Their owner sets grow from one
to eight members over eight transfers. Row presence still affects
provenance lookup, so an empty hidden-dependency set cannot justify
dropping the row.

The abstraction therefore needs two keys for projected opaque storage.
Use a stable domain key for possible aliasing and provenance recovery.
Use a current observation key for exact lookup, retirement and guarded
emptying. A historical observation can contribute a possible target via
the domain key. It cannot authorize a strong update to the current
observation. Keep historical owner associations and hidden dependencies
with their historical domain partition. If an owner can also occur in
the current value, represent that overlap as a may-relation. A definite
emptying operation can remove the current row's obligations. It can
remove obligations from the historical row only if it covers every
represented instance.

Test the transfer with two retained observations of one domain before
testing the complete loop driver. Empty the current observation while a
hidden dependency remains in an older observation. Then check that
provenance recovery still finds the possible domain, the earlier
observation cannot update the current row strongly, and ending the
earlier dependency still diagnoses an escape. Run the same trace with an
initially empty row to verify that domain membership survives aging
independently of hidden contents.

The push summary publishes both a field-zero post-value and an
aggregate post-value with possible initialization, root retirement,
and generation refresh. The aggregate recipe produces a new owner.
The field recipe includes prior owners as alternatives. A weak update
must preserve owners from the path that keeps the old allocation.
Definite replacements of exact symbolic storage retire the previous
value's owner roots before storing the new value. They leave the
physical backing and the old value's borrowed dependencies separate.

Compute loop headers by joining entry with the abstract backedge.
Compare complete states in the same partition namespace, including
storage contents and deferred effects. Accept when the backedge is
included in the header. Accumulate breaks and condition-false exits in
the same namespace while preserving their own facts. Maintain may sets
by union and definite evidence by intersection. With finite partitions,
bounded instance multiplicity and finite evidence components, a
monotone header sequence can grow only finitely often. A worklist over
changed partitions can avoid replay where transfer dependencies are
available.

Choice refinements are definite evidence. A covering header may omit
an incoming refinement, but every refinement it claims must also hold
in the incoming state. Opaque rows with the same domain identity and outcome guard compare
hidden dependencies and possible owner associations by set inclusion. Transferred-domain lookup uses those dependencies to
collect possible writes without selecting a single destination.

Before replacing the current driver, test the abstraction with a fresh
generation observed before replacement, two simultaneously live owners
from one producer, and an old projection retained through an opaque
domain. Check the aging substitution against bounded concrete traces.
Then verify inclusion for the full backedge, including fresh symbolic
writes and suspended authority. Run the dynamic array growth and
reserved-capacity controls alongside stale-view, lexical-escape and
mixed-generation rejection cases.

## Function boundary

Publish entry requirements, may-access footprint, and a conservative
normal-return transform with separate error outcomes where relevant. The
footprint includes accesses authorized internally. A body proves those
accesses using authority established at the point of operation. A caller
supplies only the required external authority. An implementation of an
abstract contract accepts its public preconditions, stays within its
footprint, and establishes its public postconditions.

For temporal effects, retain only the state transitions needed by an interface.
For a completion followed by an access, the relevant fact is that every
conflicting access is dominated by authenticated completion of the matching
receipt. For a guarded write, the evidence is that accesses occur during
the corresponding acquisition and release closes it. A flat may-effect
summary suffices for current entry-authorized calls. It cannot express
these facts, so keep the conservative rejection until a verified transform
can publish them. Avoid replaying arbitrary traces.

A regional result binds an abstract role to an evaluated instance. To use
an entry-relative route after an intermediate write, prove stability of
the reads that locate that route. A helper may return multiple covered
routes. Substitute each route independently and retain unresolved effects
where substitution cannot establish coverage. For erased heterogeneous
storage, first use guarantees common to all alternatives. If those do not
suffice, a stronger checked interface or a later explicit dynamic proof
can recover precision. No per-call virtual capability lookup is required.

## Tradeoffs and acceptance gates

| Simplification | Complexity removed | Precision cost and control |
| --- | --- | --- |
| Alias-coherent load/store/forget | Parallel interpretations of current contents | Weak updates can retain expired alternatives. Cases 232 and 233 require preserving proven disjointness and same-observation replacement. |
| Interface bounds across erasure | Reconstructing concrete providers and element histories | A heterogeneous lookup cannot always identify one provider. Case 121 needs a shared guarantee and proved independence, while 143 checks recovery through the matching receipt. |
| Derived authority from custody and loans | Mutable bookkeeping of equivalent available permissions | Custody and derived-loan ancestry still need identity. Overapproximated overlap can reject disjoint partitions. Case 177 requires a real backing bound. |
| Compact state transforms | Full effect traces and repeated callee analysis | Some finish-and-write helpers remain conservative. Preserve order only where it changes the safety proof. |
| Widen old observations | Unbounded identities per call and loop | A repair of a newly evaluated pointer cannot kill an old write. Cases 234 and 237 require repair through a stable observation before use or reevaluation. |

For a String, prove access to its bytes separately from the latent virtual
deallocation operation. A live provider with exclusive handoff, synchronized
release, or certified delegated cleanup can justify different transitions
under the same rules. An executor outside core needs a documented audited
protocol for ingress, single admission, rollback before admission, and
completion with publication. A mutex needs the same custody rules plus
acquisition-scoped exclusion. Core privacy controls who can invoke trusted
operations. It is not evidence that their physical or publication contracts
hold.

## Migration and falsification

1. Make reads of reference-bearing cells go through one content query. Start
   with summary substitution, using the observed store as a reaching-write
   domain. Keep address-only and snapshot consumers explicit. Check aliases,
   weak writes, aggregate leaves, and expired-but-unused references.
2. Publish residual writes and complete destination evidence through the same
   caller-relative interface. Cases 229/231 with stronger regional contracts
   test capture stability and helper forwarding. Case 288 is an entry-capture
   control. Case 289X must still reject a provider that can target global
   storage. If a public contract admits an unbounded target, the compiler
   must keep the residual rather than inspect the erased provider.
3. Use the same typed load for known array candidate contents and view spans
   after a verified range proof. Case 115 checks ergonomics. Cases 285X,
   301X, 305X and 306X test escaping dependencies and raw offsets. Backing
   identity is too weak for typed element coverage, particularly across rows.
4. Only after those boundaries compose, validate move-and-cleanup and
   acquire-and-release as state transforms. Exercise partial launch, wrong
   and duplicate completion, multiple readers, stale guards after
   reacquisition, derived loans, and cleanup with an incompatible provider.
5. Remove per-consumer content overlays only after their behavior is supplied
   by the common query. Remove duplicate permission bookkeeping only after
   custody and pending obligations reproduce every authorization decision.

The bounded Zig observed-store oracle checks that joined branches and later
updates cover concrete outcomes under alias valuations. The Python resource
model independently exercises loans, owner cleanup, and protection. Neither
proves the compiler's abstraction. The missing bridge is a refinement
argument for each production load/store and summary substitution, backed by
paired compiler fixtures. If that argument requires treating syntactically
repeated calls as one reference or inventing a library-specific permission,
the representation must change before the feature is extended.

## Baseline comparison

The isolated `fe902869e` ReleaseSafe runner passed all seven named
concurrency acceptance fixtures (121, 143, 177, 232, 233, 234, 237).
The integrated compiler also built and ran all seven. Compile-only copies
of the incomplete target, caller read, and repeated observation
reductions all built on the published baseline. The integrated compiler
rejected the first and third for an ended dependency and the caller-read
case for a borrow escaping into caller storage. No reduction executable
was run. The integrated observed-store selection passed 12 unit tests.
The resource model passed its bounded exploration, including 4,951 states
and 7,472 accepted combined steps at depth four.

### Summary content query migration

The integrated checker now routes ordinary result contents and opaque
dependency collection through the same input-place loader. Its coordinate
convention starts at the immediate referent, unlike a general path over an
evaluated argument. Both concrete and symbolic storage reconstruct their
structural contents before applying the typed reaching-write query also
used by ordinary reads. Address and snapshot consumers remain separate.

The concrete and opaque increment passed 155 ReleaseSafe program checks,
including the seven acceptance fixtures and 240X through 242X. Internal
regressions check that an aggregate load retains both the prior reference
and a possibly written reference, and that a symbolic slot contributes its
stored dependency to an opaque summary without contributing the slot's own
backing lifetime. The symbolic aggregate migration also passed the focused
79-test internal summary run. It requires a separate program validation.

The symbolic aggregate change passed the same 155 program checks. The
next run included implicit referent loading, captured-region execution
retention, and all concurrency and opaque checks plus the stale FFI
capability cases. It passed 441 checks with no skips. Only 229 and 231
failed, with their existing unresolved-destination diagnostics. This
establishes the tested load migration independently of the remaining
destination-publication problem. It does not test collection case 115.

### What distinguishes the two repair fixtures

Compile-only controls for 229 and 231 isolate destination lifetime from
the repair of the original slot. Keeping the whole helper unchanged and
moving only its replacement referent to static storage allows both builds.
Keeping the lexical replacement and changing the getter to return a global
slot rejects both builds. This second implementation satisfies the same
published lifetime contract as the original getter (see also 258X).
Repairing the original slot cannot undo a store to a different slot.

A modular caller with only that contract has to account for both
implementations. Accepting the original lexical replacements therefore
requires some additional verified restriction on the destination, or
evidence retained at construction that the caller can instantiate across
the helper. A better local strong update alone cannot distinguish these
programs. The existing fixture expectations remain acceptance targets for
that additional precision.

### Acquired destinations and local reference escape

Execution fixture 255 supplies a useful control independent of view sorting.
Starting with its typed two-element allocation, writing the borrowed record
only to the indexed first slot is already rejected. Removing that store
allows compilation. Writing only to the offset second slot fails with the
same escape diagnostic. Moving both borrowed integers to global storage
allows the original two writes to compile. These are compile-only controls.

This separates two proof obligations. At slot establishment the runtime
checks the address range and, for an explicit index, the expected address.
The checker should be able to associate that destination with the allocation
whose contents retain the stored dependencies. A write must constrain any
later move, return or transfer of the owner. A local binding for the owner
is insufficient if it subsequently escapes. For a borrowed backing, those
obligations must instead follow the actual destination storage. The anchor
supplies a lifetime bound and cannot identify either destination.

Only the second store additionally needs proof that a typed offset stays
inside the original extent. A raw offset into an adjacent allocation cannot
inherit the first slot's destination. Collection case 115 needs the same
range check but starts from a lexical array with an already known identity.
Test the first-slot case independently before adding offset precision.

### Program suite baseline after the summary join changes

On Linux, ReleaseSafe program validation at `975be6641` passed 226 shared
cases, skipped 10 and failed the geometry kernel with an ended-root
diagnostic in `_extrusion_buffers`. The build step gates all 16 fixture
workers on the shared run, so the workers were invoked separately with
the same installed bundle and runner. They passed 2,521 cases, skipped one
and failed 28 with zero leaks. The failed fixture identities match the
earlier `0d485` run, which passed 2,512 worker cases.

### Commit-time authority across an ordinary call

Fixture 448 checks that direct, indirect, field and array assignments can
complete a pending loan while evaluating the right-hand side. Fixture
447X checks the reverse transition, where evaluation creates an overlapping
loan before the store. Fixture 449X checks a separate dimension: the same
evaluation can retire the captured destination without leaving any pending
execution.

A compile-only control at `a1911ffb6` extracts the safe indirect assignment
into a helper taking the destination and the future. The caller rejects
the helper with the same overlap diagnostic as a control that stores
before completing the future. The access summary is checked against entry
authority, while completion is published only at return. To distinguish
the two controls, an access requirement must record which completions
dominate that access on every path. The corresponding receipt identities
must come from evaluated arguments. A completion on one alternative, or
after an access, cannot discharge its requirement.

### Opaque obligations at loop joins

The loop audit established that a pending loan cannot follow an ownership
generation substitution through the value alone. Opaque storage presents
the same problem when it retains the original generation independently.
The conservative guard at `5054f085f` also rejects three serial fixtures
that compile at its parent `912e9511b`: word count, CSV decoding and URI
parsing. In all three the rejected access depends on a growable buffer
after a loop. A control on later code restricting the owner-root check to
domains with nonempty hidden dependencies still rejects word count.

The repair must preserve a retirement obligation for each reachable
alternative. Retention in a domain owned by the same current value may
follow the value only when each incoming state establishes that
relationship. An external or historical domain must retain its original
generation. The fixture contrast prevents treating the opaque store as
always external or assuming that merged owner roots prove that it is
internal.

Tracing word count at `5054f085f` identifies a domain under the buffer
binding whose hidden dependency set is empty and whose owner identities
contain both incoming backing roots. Those identities alone trigger the
first rejection of widening. At the current revision, allowing empty
memberships to pass the widening guard and remapping the memberships
under the owner still leaves the ended-root diagnostic. The change that
first exposes the regression and the conditions needed to repair it on
the current checker are therefore distinct. Preserve the controls for
historical aliases and pending receipts when investigating the remaining
canonical-root reuse check.

After bypassing the empty-domain guard in a diagnostic build, the
canonical-root guard triggers. The only place retaining that root in
word count is the buffer value itself. The entry has one owned root and
does not observe the canonical root. The backedge has two possible
owned roots and still observes the canonical root, whose state is
`maybe_alive`. Ownership membership cannot distinguish a live observation
from a stale one at that point. The proof has to survive the join that
produced the backedge value.

On Linux the `a1911ffb6` program run recorded 223 passed, 10 skipped and
four failed serial fixtures. In a separate invocation of the same
runner, the 16 groups recorded 2,520 passed, one skipped and 36 failed.
Relative to `1891bfddd`, authenticated dynamic acquisition recovered
and eight worker fixtures began failing. The eight are collection
fixtures 150 and 166, I/O fixtures 39 through 41, system fixtures 86 and
88, and text fixture 76. This comparison identifies the changed failure
set without attributing every failure to a single change.

### Owned transfer compiler cost after the reference projection changes

Five alternating cold builds per revision on Linux compare `1891bfddd`
with `531d20a63`. Both compilers are Debug Zig builds. Both use one frontend
worker, disable the frontend cache and emit LLVM IR. Wall time, peak RSS
and the GlobalSafety phase are medians. Executable code size is the ELF
`.text` section.

| Fixture | Wall time, s | Peak RSS, MiB | GlobalSafety, ms | LLVM functions | Code bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| 431 Allocation | 1.81 → 1.83 | 141.02 → 141.38 | 90.586 → 91.947 | 166 → 166 | 165263 → 165263 |
| 433 String | 3.07 → 3.04 | 149.72 → 149.32 | 205.572 → 204.075 | 256 → 256 | 286751 → 286751 |

Generic instantiation calls and reuse counts also agree between revisions:
1435 calls and 253 existing instances for Allocation, and 2942 calls and
568 existing instances for String. These are activity counters, while
the LLVM function count measures emitted functions. The sample covers
two transfer paths and does not estimate scaling with branch count or
outstanding loans.

### Cost of overlapping loan lifetimes

A generated program declares one separate `Int32` binding per task,
borrows each binding mutably into the same worker, and awaits each
receipt. The pending case starts all tasks before awaiting the first.
The serial control awaits each task immediately after submission. Both
use the same declarations and calls, with no benchmark execution.
Three alternating builds on Linux used the Debug compiler at
`531d20a63`, one frontend worker and a disabled frontend cache.

| Tasks | GlobalSafety pending / serial, ms | Wall time pending / serial, s | Peak RSS pending / serial, MiB |
| ---: | ---: | ---: | ---: |
| 8 | 71.8 / 71.4 | 1.37 / 1.38 | 139.2 / 139.3 |
| 32 | 174.0 / 172.8 | 2.53 / 2.56 | 143.5 / 143.6 |
| 128 | 1162.2 / 1169.9 | 7.79 / 7.69 | 167.7 / 167.6 |

Both patterns grow substantially with the number of tasks. At the
measured sizes the cost from having all loans pending does not stand
out in whole-phase timings. Both patterns retain execution identities,
so the comparison does not isolate scans of completed executions from
other safety work. Measure the individual authority queries before
using this benchmark to justify a region index.
