"""Bounded design experiment, not the compiler's safety implementation or proof.

Run: python3 tools/resource_authority_model.py
A single allocation has two bytes. Grants are resolved per byte, so differently
named or differently sized regions cannot conceal overlap. Generations validate
observations; they never establish physical separation.
"""
from dataclasses import dataclass, replace
from itertools import product

READ, WRITE = 1, 2
REGIONS = ((0,), (1,), (0, 1))


class Denied(Exception):
    pass


@dataclass(frozen=True)
class Loan:
    source: int
    target: int
    region: tuple[int, ...]
    mode: int
    generation: int
    pending: bool = True


@dataclass(frozen=True)
class Acquisition:
    execution: int
    region: tuple[int, ...]
    generation: int
    active: bool = True


@dataclass(frozen=True)
class State:
    initial: tuple[int, int] = (WRITE, WRITE)
    generation: int = 0
    live: bool = True
    loans: tuple[Loan, ...] = ()
    protected: frozenset[int] = frozenset()
    acquisitions: tuple[Acquisition, ...] = ()

    def authority(self, execution, byte):
        if not self.live:
            return 0
        if byte in self.protected:
            return WRITE if any(a.active and a.execution == execution and byte in a.region
                                for a in self.acquisitions) else 0
        grant = self.initial[byte] if execution == 0 else 0
        for loan in self.loans:
            if loan.pending and loan.target == execution and byte in loan.region:
                grant = max(grant, loan.mode)
        for loan in self.loans:
            if loan.pending and loan.source == execution and byte in loan.region:
                if loan.mode == WRITE:
                    return 0
                grant = min(grant, READ)
        return grant

    def access(self, execution, region, mode, generation=None, guard=None):
        if generation is not None and generation != self.generation:
            raise Denied("stale observation")
        if any(b in self.protected for b in region):
            if guard is None or not 0 <= guard < len(self.acquisitions):
                raise Denied("protected storage requires acquisition-derived route")
            acquired = self.acquisitions[guard]
            if (not acquired.active or acquired.execution != execution or
                    acquired.generation != self.generation or
                    not set(region).issubset(acquired.region)):
                raise Denied("expired or mismatched acquisition")
        if not self.live or any(self.authority(execution, b) < mode for b in region):
            raise Denied("insufficient authority")

    def lend(self, source, target, region, mode):
        if source == target or target == 0:
            raise Denied("not a fresh child execution")
        # Execution IDs are never reused. This bounded experiment intentionally
        # excludes tasks with several inputs and dynamic authority merging.
        if any(loan.target == target for loan in self.loans):
            raise Denied("execution identity already used")
        self.access(source, region, mode)
        return replace(self, loans=self.loans + (Loan(source, target, region, mode, self.generation),))

    def complete(self, receipt, *, quiescent=True, published=True):
        if not 0 <= receipt < len(self.loans):
            raise Denied("unknown receipt")
        loan = self.loans[receipt]
        if not loan.pending or not quiescent or not published:
            raise Denied("completion not certified")
        # A worker cannot release borrowed resources while its children retain
        # them. Ending the physical parent worker is not enough.
        if any(child.pending and child.source == loan.target for child in self.loans):
            raise Denied("child obligation remains")
        if not self.live or loan.generation != self.generation:
            raise Denied("ended loan observation")
        return replace(self, loans=tuple(replace(x, pending=False) if i == receipt else x
                                        for i, x in enumerate(self.loans)))

    def renew(self):
        if self.protected:
            raise Denied("protected authority must return before replacement")
        if any(loan.pending for loan in self.loans):
            raise Denied("outstanding use prevents invalidation")
        self.access(0, (0, 1), WRITE)
        return replace(self, generation=self.generation + 1)

    def protect(self, region):
        self.access(0, region, WRITE)
        return replace(self, protected=self.protected | frozenset(region))

    def acquire(self, execution, region, *, synchronized=True):
        if not synchronized or not set(region).issubset(self.protected):
            raise Denied("no certified protected acquisition")
        if any(a.active and set(a.region) & set(region) for a in self.acquisitions):
            raise Denied("protected authority already acquired")
        return replace(self, acquisitions=self.acquisitions +
                       (Acquisition(execution, region, self.generation),))

    def release(self, guard, execution, *, published=True):
        if not 0 <= guard < len(self.acquisitions):
            raise Denied("unknown acquisition")
        acquired = self.acquisitions[guard]
        if (not acquired.active or acquired.execution != execution or not published or
                acquired.generation != self.generation):
            raise Denied("uncertified or mismatched release")
        return replace(self, acquisitions=tuple(replace(a, active=False) if i == guard else a
                                               for i, a in enumerate(self.acquisitions)))

    def check(self):
        for byte in range(2):
            modes = [self.authority(e, byte) for e in range(3)]
            assert sum(mode == WRITE for mode in modes) <= 1
            if WRITE in modes:
                assert sum(mode != 0 for mode in modes) == 1
            assert all(mode <= self.initial[byte] for mode in modes)
        for loan in self.loans:
            if loan.pending:
                assert self.live and loan.generation == self.generation
                assert not set(loan.region) & self.protected
        for acquired in self.acquisitions:
            if acquired.active:
                assert self.live and acquired.generation == self.generation
                assert set(acquired.region).issubset(self.protected)


def denied(action):
    try:
        action()
    except Denied:
        return
    raise AssertionError("unsafe transition was accepted")


def adversarial_traces():
    original = State()
    readers = original.lend(0, 1, (0, 1), READ).lend(0, 2, (0,), READ)
    one_done = readers.complete(0)
    denied(lambda: one_done.access(0, (0,), WRITE))
    one_done.access(0, (1,), WRITE)
    one_done.complete(1).access(0, (0, 1), WRITE)
    readonly = State(initial=(READ, READ)).lend(0, 1, (0,), READ).complete(0)
    denied(lambda: readonly.access(0, (0,), WRITE))
    writer = original.lend(0, 1, (0,), WRITE)
    denied(lambda: writer.access(0, (0,), READ))
    writer.access(0, (1,), WRITE)
    denied(lambda: writer.renew())
    denied(lambda: writer.complete(7))
    denied(lambda: writer.complete(0, quiescent=False))
    denied(lambda: writer.complete(0, published=False))
    done = writer.complete(0)
    denied(lambda: done.complete(0))
    denied(lambda: done.renew().access(0, (0,), READ, generation=0))
    nested = writer.lend(1, 2, (0,), READ)
    denied(lambda: nested.complete(0))
    denied(lambda: nested.access(1, (0,), WRITE))
    nested.complete(1).complete(0).access(0, (0,), WRITE)
    split = original.lend(0, 1, (0,), WRITE).lend(0, 2, (1,), WRITE)
    split.check()
    denied(lambda: writer.lend(0, 2, (0, 1), READ))


def explore(depth=5):
    frontier = {State(initial=modes) for modes in product((READ, WRITE), repeat=2)}
    seen = set(frontier)
    transitions = 0
    for _ in range(depth):
        following = set()
        for state in frontier:
            state.check()
            actions = [lambda i=i: state.complete(i) for i in range(len(state.loans))]
            for source, target, region, mode in product(range(3), (1, 2), REGIONS, (READ, WRITE)):
                actions.append(lambda s=source, t=target, r=region, m=mode: state.lend(s, t, r, m))
            for action in actions:
                try:
                    result = action()
                except Denied:
                    continue
                result.check()
                transitions += 1
                if result not in seen:
                    following.add(result)
        seen.update(following)
        frontier = following
    return len(seen), transitions


@dataclass(frozen=True)
class Access:
    region: tuple[int, ...]
    mode: int


@dataclass(frozen=True)
class Complete:
    receipt: int
    success: bool = True


@dataclass(frozen=True)
class UnknownAccess:
    pass


def execute(state, trace):
    """Semantic reference interpreter; traces are NOT proposed compiler IR.

    Failed completion leaves obligations pending. Unknown access may touch any
    byte, but grants no authority. No task or function name has special meaning.
    """
    for event in trace:
        if isinstance(event, Access):
            state.access(0, event.region, event.mode)
        elif isinstance(event, Complete):
            if event.success:
                state = state.complete(event.receipt)
        elif isinstance(event, UnknownAccess):
            state.access(0, (0, 1), WRITE)
        else:
            raise TypeError(event)
        state.check()
    return state


@dataclass(frozen=True)
class Transformer:
    # Explicit finite alternatives provide an oracle for comparing candidate
    # abstractions. They are unsuitable as unbounded production summaries.
    paths: tuple[tuple, ...]

    def apply(self, inputs):
        outputs = set()
        for state in inputs:
            for trace in self.paths:
                # One unsafe alternative rejects the call. Unioning only
                # successful executions would silently discard obligations.
                outputs.add(execute(state, trace))
        return frozenset(outputs)

    def then(self, other):
        return Transformer(tuple(a + b for a in self.paths for b in other.paths))


def transformer_experiments():
    writer = State().lend(0, 1, (0,), WRITE)
    finish = Transformer(((Complete(0),),))
    write = Transformer(((Access((0,), WRITE),),))
    combined = finish.then(write)
    assert combined.apply((writer,)) == write.apply(finish.apply((writer,)))
    denied(lambda: write.then(finish).apply((writer,)))
    # Identical unordered may-access/completion sets do not imply identical
    # resource transformers: the preceding two functions have different domains.
    conditional = Transformer(((Complete(0),), (Complete(0, success=False),)))
    denied(lambda: conditional.then(write).apply((writer,)))
    two_tasks = writer.lend(0, 2, (1,), WRITE)
    denied(lambda: Transformer(((Complete(1), Access((0,), WRITE)),)).apply((two_tasks,)))
    # Losing correlation by erasure must check every retained alternative.
    other_writer = State().lend(0, 1, (1,), WRITE)
    safe_input = State()
    denied(lambda: write.apply((safe_input, writer)))
    assert len(write.apply((safe_input, other_writer))) == 2
    # Unknown calls may write every byte. Completion of one task cannot hide a
    # second outstanding use; once all grants return the same call is allowed.
    unknown = Transformer(((UnknownAccess(),),))
    denied(lambda: finish.then(unknown).apply((two_tasks,)))
    finish.then(unknown).apply((writer,))
    # A failed branch can return without touching borrowed storage. Its pending
    # obligation must survive in that outcome instead of being globally erased.
    outcomes = Transformer(((Complete(0), Access((0,), WRITE)), ())).apply((writer,))
    assert any(state.loans[0].pending for state in outcomes)
    assert any(not state.loans[0].pending for state in outcomes)
    denied(lambda: write.apply(outcomes))

    # Exhaustively compare modular composition with straight-line execution for
    # a small family, including calls that legitimately reject their inputs.
    atoms = ((), (Complete(0),), (Complete(0, success=False),),
             (Access((0,), READ),), (Access((0,), WRITE),),
             (Access((1,), WRITE),), (UnknownAccess(),))
    checked = 0
    for state, left, right in product((safe_input, writer, other_writer, two_tasks), atoms, atoms):
        a, b = Transformer((left,)), Transformer((right,))
        try:
            direct = a.then(b).apply((state,))
        except Denied:
            denied(lambda: b.apply(a.apply((state,))))
        else:
            assert direct == b.apply(a.apply((state,)))
        checked += 1
    return checked


@dataclass(frozen=True)
class Requirement:
    after: frozenset[int]
    event: object


@dataclass(frozen=True)
class CompletionSummary:
    """Candidate finite abstraction for completion-only resource transitions.

    No lending, generation changes, ownership or protected acquisition is modeled.
    Requirements are checked universally; only guaranteed final completions flow
    to subsequent calls. Missing precision costs acceptance, never authority.
    """
    requirements: frozenset[Requirement]
    completed: frozenset[int]
    unsupported: bool = False

    @staticmethod
    def infer(transformer):
        requirements = set()
        exits = []
        unsupported = False
        for trace in transformer.paths:
            completed = set()
            for event in trace:
                if isinstance(event, Complete) and not event.success:
                    continue
                if isinstance(event, Complete) and event.receipt in completed:
                    unsupported = True  # Never deduplicate a double discharge.
                requirements.add(Requirement(frozenset(completed), event))
                if isinstance(event, Complete):
                    completed.add(event.receipt)
            exits.append(completed)
        guaranteed = set.intersection(*exits) if exits else set()
        return CompletionSummary(frozenset(requirements), frozenset(guaranteed), unsupported)

    @staticmethod
    def discharge(state, receipts):
        # This ordering is deliberately conservative. A general implementation
        # needs a verified dependency order, not guessed numeric receipt order.
        for receipt in sorted(receipts):
            state = state.complete(receipt)
        return state

    def apply(self, state):
        if self.unsupported:
            raise Denied("unsupported repeated completion")
        for requirement in self.requirements:
            before = self.discharge(state, requirement.after)
            execute(before, (requirement.event,))
        return self.discharge(state, self.completed)

    def then(self, other):
        # Requirements of the second call can rely only on unconditional
        # completion guarantees of the first. A receipt cannot be discharged
        # twice across the call boundary either.
        repeated = bool(self.completed & other.completed)
        following = frozenset(Requirement(r.after | self.completed, r.event)
                              for r in other.requirements)
        return CompletionSummary(self.requirements | following,
                                 self.completed | other.completed,
                                 self.unsupported or other.unsupported or repeated)


def summary_experiments():
    initial = State()
    writer = initial.lend(0, 1, (0,), WRITE)
    other = initial.lend(0, 1, (1,), WRITE)
    inputs = (initial, writer, other, writer.lend(0, 2, (1,), WRITE))
    alphabet = (Complete(0), Complete(0, success=False), Complete(1),
                Access((0,), READ), Access((0,), WRITE), Access((1,), WRITE), UnknownAccess())
    traces = [trace for length in range(4) for trace in product(alphabet, repeat=length)]
    cases = [Transformer((trace,)) for trace in traces]
    # Include control-flow alternatives, with no outcome correlation retained.
    cases += [Transformer(((), trace)) for trace in traces]
    checked = accepted = 0
    for transformer, state in product(cases, inputs):
        summary = CompletionSummary.infer(transformer)
        checked += 1
        try:
            abstract = summary.apply(state)
        except Denied:
            continue
        concrete = transformer.apply((state,))  # Raises if any accepted path is unsafe.
        for output in concrete:
            # The abstract state overapproximates possible outstanding workers
            # and underapproximates authority of the calling execution only.
            # A completed child has no usable caller-visible execution context.
            for byte in range(2):
                assert abstract.authority(0, byte) <= output.authority(0, byte)
            # An abstract post-state may keep a completed obligation pending,
            # but must never drop one pending in a concrete outcome.
            assert all(a.pending or not c.pending for a, c in zip(abstract.loans, output.loans))
        accepted += 1
    finish = CompletionSummary.infer(Transformer(((Complete(0),),)))
    write = CompletionSummary.infer(Transformer(((Access((0,), WRITE),),)))
    finish.then(write).apply(writer)
    denied(lambda: write.then(finish).apply(writer))
    branch = CompletionSummary.infer(Transformer(((Complete(0),), ())))
    denied(lambda: branch.then(write).apply(writer))
    return checked, accepted


def instantiate_summary(summary, receipts, regions):
    """Substitute evaluated observations, not mutable parameter-slot names.

    This experiment maps formal receipt indices to immutable loan identities.
    Retargetable inputs require a separate flow proof and are not represented.
    """
    requirements = set()
    for requirement in summary.requirements:
        after = frozenset(receipts[i] for i in requirement.after)
        event = requirement.event
        if isinstance(event, Complete):
            event = Complete(receipts[event.receipt], event.success)
        elif isinstance(event, Access):
            event = Access(tuple(sorted({b for i in event.region for b in regions[i]})), event.mode)
        requirements.add(Requirement(after, event))
    return CompletionSummary(frozenset(requirements),
                             frozenset(receipts[i] for i in summary.completed),
                             summary.unsupported)


def substitution_experiments():
    state = State().lend(0, 1, (0,), WRITE).lend(0, 2, (1,), WRITE)
    formal = CompletionSummary.infer(Transformer(((Complete(0), Access((0,), WRITE)),)))
    instantiate_summary(formal, {0: 0}, {0: (0,)}).apply(state)
    denied(lambda: instantiate_summary(formal, {0: 1}, {0: (0,)}).apply(state))
    # One formal region may denote several alternatives. Completing a task for
    # only one alternative does not authorize the combined ordinary access.
    denied(lambda: instantiate_summary(formal, {0: 0}, {0: (0, 1)}).apply(state))
    # Distinct formal inputs do not prove distinct obligations. Substitution
    # must preserve duplicate-discharge rejection when both alias one receipt.
    twice = CompletionSummary.infer(Transformer(((Complete(0), Complete(1)),)))
    denied(lambda: instantiate_summary(twice, {0: 0, 1: 0}, {}).apply(state))
    # An evaluated observation survives later replacement of its source slot.
    slots = {0: 0}
    evaluated = instantiate_summary(formal, dict(slots), {0: (0,)})
    slots[0] = 1
    evaluated.apply(state)
    denied(lambda: instantiate_summary(formal, slots, {0: (0,)}).apply(state))


def protected_experiments():
    initial = State()
    protected = initial.protect((0,))
    denied(lambda: protected.access(0, (0,), READ))
    protected.access(0, (1,), WRITE)
    held = protected.acquire(1, (0,))
    held.check()
    held.access(1, (0,), WRITE, guard=0)
    held.access(1, (0,), READ, guard=0)  # Several aliases use one grant.
    denied(lambda: held.access(1, (0,), WRITE))  # An old route still cannot bypass it.
    denied(lambda: held.access(0, (0,), READ, guard=0))
    denied(lambda: held.access(1, (1,), READ, guard=0))
    denied(lambda: held.acquire(2, (0,)))
    denied(lambda: held.release(0, 2))
    denied(lambda: held.release(0, 1, published=False))
    released = held.release(0, 1)
    denied(lambda: released.access(1, (0,), READ, guard=0))
    denied(lambda: released.release(0, 1))
    again = released.acquire(2, (0,))
    again.access(2, (0,), WRITE, guard=1)
    denied(lambda: again.access(2, (0,), READ, guard=0))
    # Encapsulation fails if another execution still has ordinary access.
    borrowed = initial.lend(0, 1, (0,), READ)
    denied(lambda: borrowed.protect((0,)))
    denied(lambda: initial.acquire(1, (0,)))
    denied(lambda: protected.acquire(1, (0,), synchronized=False))
    denied(lambda: protected.renew())
    # Different protected regions may be acquired independently, not merely
    # different names for overlapping bytes.
    split = initial.protect((0, 1)).acquire(1, (0,)).acquire(2, (1,))
    split.check()
    split.access(1, (0,), WRITE, guard=0)
    split.access(2, (1,), WRITE, guard=1)


if __name__ == "__main__":
    adversarial_traces()
    substitution_experiments()
    protected_experiments()
    compositions = transformer_experiments()
    summaries_checked, summaries_accepted = summary_experiments()
    states, transitions = explore()
    print(f"Authority experiment: {states} states, {transitions} accepted transitions; invariants hold")
    print(f"Resource transformer experiment: {compositions} modular compositions checked")
    print(f"Completion summaries: {summaries_checked} cases checked, {summaries_accepted} accepted conservatively")
    print("Receipt/region substitution adversarial cases passed")
    print("Protected-access adversarial traces passed (not included in the exhaustive loan exploration)")
    print("Scope: two bytes, three executions, at most two loans, depth five; not a soundness proof")
