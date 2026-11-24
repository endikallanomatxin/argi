# Ownership transfer and static safety evidence

The type defines the interface and physical representation. Value facts describe
guarantees of the current contents. Safety state authorizes the operation at
the point where ownership crosses an execution boundary.

A nominal type's owner may publish Transferable when the guarantee holds for
every valid value of that type. The guarantee covers use and eventual cleanup in
the receiving execution. Temporal dependencies, pending loans and cleanup
ownership remain separate obligations. A type guarantee grants no permission to
transfer a reference to the type.

Virtual construction can carry static evidence about the actual captured
capability, including its receiver permission and retained dependencies. Two
handles for the same contract can have different evidence. Derive aggregate
evidence from the current components. At joins, retain guarantees supported by
every alternative. Use the existing reference-write and post-state machinery to
replace evidence or drop it when the affected contents cannot be resolved.

Represent summary requirements as bounded conjunctions of input guarantees.
Check ownership transfer before native submission and preserve cleanup through
failure, completion and result transport. Evidence is compiler state and takes
no space in values, virtual tables or specialization keys.

Validate the same String type and submission specialization with a shareable
deallocation capability and with a local provider. Cover forwarding, joins,
alias replacement, stale dependencies, outstanding loans and failure cleanup.
Measure compiler time and peak memory alongside generated code and specialization
counts. The existing sequential reference-content regressions remain separate
obligations.

## Native input handoff

The current task adapter copies its input bytes before attempting to start the
worker. For an owning input, treat this copy as provisional until submission
succeeds. A failed start discards the provisional bytes and the submitting
scope cleans up its original value. An accepted start authorizes exactly one
worker to consume the copy. The submitting scope then retires its original
cleanup obligation without invoking it. Inline submission follows the same
ownership rule, including when the worker has already completed on return.

The acceptance proof must originate at the authenticated native submission.
Carry it through TaskRequest and executor results so a provider cannot
manufacture acceptance, submit a request twice, or disguise acceptance as a
failure that would reactivate sender cleanup. The receipt retains execution
loans until completion. Its lifetime and the actual result's transfer evidence
are separate from ownership of the request input.
