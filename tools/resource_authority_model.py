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
    acquisition: int | None = None


@dataclass(frozen=True)
class Protection:
    region: tuple[int, ...]
    generation: int


@dataclass(frozen=True)
class Acquisition:
    execution: int
    region: tuple[int, ...]
    generation: int
    active: bool = True
    protocol: int = 0


@dataclass(frozen=True)
class Owner:
    holder: int
    payload: tuple[int, ...]
    cleanup: tuple[tuple[tuple[int, ...], int], ...]
    active: bool = True


@dataclass(frozen=True)
class State:
    initial: tuple[int, int] = (WRITE, WRITE)
    residence: tuple[int, int] = (0, 0)
    retired: frozenset[int] = frozenset()
    owners: tuple[Owner, ...] = ()
    generation: int = 0
    live: bool = True
    loans: tuple[Loan, ...] = ()
    protected: frozenset[int] = frozenset()
    protections: tuple[Protection, ...] = ()
    acquisitions: tuple[Acquisition, ...] = ()

    def authority(self, execution, byte):
        if not self.live or byte in self.retired:
            return 0
        if byte in self.protected:
            grant = WRITE if any(a.active and a.execution == execution and byte in a.region
                                 for a in self.acquisitions) else 0
        else:
            grant = self.initial[byte] if execution == self.residence[byte] else 0
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
            protected_region = set(region) & self.protected
            derived = any(loan.pending and loan.target == execution and
                          loan.acquisition == guard and loan.mode >= mode and
                          protected_region.issubset(loan.region) for loan in self.loans)
            if (not acquired.active or (acquired.execution != execution and not derived) or
                    acquired.generation != self.generation or
                    not protected_region.issubset(acquired.region)):
                raise Denied("expired or mismatched acquisition")
        if not self.live or any(self.authority(execution, b) < mode for b in region):
            raise Denied("insufficient authority")

    def lend(self, source, target, region, mode, *, guard=None):
        if source == target or target == 0:
            raise Denied("not a fresh child execution")
        # Execution IDs are never reused. This bounded experiment intentionally
        # excludes tasks with several inputs and dynamic authority merging.
        if any(loan.target == target for loan in self.loans):
            raise Denied("execution identity already used")
        self.access(source, region, mode, guard=guard)
        origin = guard if set(region) & self.protected else None
        return replace(self, loans=self.loans +
                       (Loan(source, target, region, mode, self.generation, acquisition=origin),))

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
        if not region:
            raise Denied("this bounded fragment models nonempty protected payloads only")
        self.access(0, region, WRITE)
        return replace(self, protected=self.protected | frozenset(region),
                       protections=self.protections + (Protection(region, self.generation),))

    def acquire(self, execution, region, *, synchronized=True, protocol=None):
        if not synchronized or not set(region).issubset(self.protected):
            raise Denied("no certified protected acquisition")
        candidates = tuple(i for i, p in enumerate(self.protections)
                           if region and set(region).issubset(p.region))
        if protocol is None:
            if len(candidates) != 1:
                raise Denied("acquisition requires one matching protocol instance")
            protocol = candidates[0]
        if protocol not in candidates:
            raise Denied("protocol does not protect the requested observation")
        protection = self.protections[protocol]
        if protection.generation != self.generation or not self.live:
            raise Denied("stale protocol custody")
        # The requested view may be smaller, but acquiring this mutex still
        # excludes its whole payload. Subranges are not independent lock IDs.
        if any(a.active and a.protocol == protocol for a in self.acquisitions):
            raise Denied("protected authority already acquired")
        return replace(self, acquisitions=self.acquisitions +
                       (Acquisition(execution, protection.region, self.generation,
                                    protocol=protocol),))

    def release(self, guard, execution, *, published=True):
        if not 0 <= guard < len(self.acquisitions):
            raise Denied("unknown acquisition")
        acquired = self.acquisitions[guard]
        if (not acquired.active or acquired.execution != execution or not published or
                acquired.generation != self.generation):
            raise Denied("uncertified or mismatched release")
        if any(loan.pending and loan.acquisition == guard for loan in self.loans):
            raise Denied("derived execution loan still uses this acquisition")
        return replace(self, acquisitions=tuple(replace(a, active=False) if i == guard else a
                                               for i, a in enumerate(self.acquisitions)))

    def establish_owner(self, holder, payload, cleanup=()):
        self.access(holder, payload, WRITE)
        if any(set(region) & self.retired for region, _ in cleanup):
            raise Denied("latent cleanup dependency is already invalid")
        if any(o.active and set(o.payload) & set(payload) for o in self.owners):
            raise Denied("cleanup responsibility already exists")
        # This transition stands for audited acquisition, never an ordinary
        # constructor authorized solely by having a writable reference.
        return replace(self, owners=self.owners + (Owner(holder, payload, cleanup),))

    def handoff(self, owner, source, target):
        value = self.owners[owner]
        if not value.active or value.holder != source:
            raise Denied("no source cleanup responsibility")
        self.access(source, value.payload, WRITE)
        # Latent external cleanup is checked before accepting the responsibility.
        # This fragment models ordinary access only, not synchronized cleanup.
        for region, mode in value.cleanup:
            self.access(target, region, mode)
        residence = tuple(target if b in value.payload else e for b, e in enumerate(self.residence))
        owners = tuple(replace(o, holder=target) if i == owner else o for i, o in enumerate(self.owners))
        return replace(self, residence=residence, owners=owners)

    def cleanup_owner(self, owner, execution):
        value = self.owners[owner]
        if not value.active or value.holder != execution:
            raise Denied("cleanup responsibility unavailable")
        self.access(execution, value.payload, WRITE)
        for region, mode in value.cleanup:
            self.access(execution, region, mode)
        # Latent cleanup retains a validity obligation independently of current
        # authority. Owning the provider does not permit ending it underneath a
        # different live owner's future cleanup operation.
        for i, retained in enumerate(self.owners):
            if i == owner or not retained.active:
                continue
            if any(set(region) & set(value.payload) for region, _ in retained.cleanup):
                raise Denied("another owner retains this cleanup dependency")
        return replace(self, retired=self.retired | frozenset(value.payload),
                       owners=tuple(replace(o, active=False) if i == owner else o
                                    for i, o in enumerate(self.owners)))

    def check(self):
        assert self.protected == frozenset(b for p in self.protections for b in p.region)
        for i, protection in enumerate(self.protections):
            assert protection.generation == self.generation and self.live
            assert not set(protection.region) & self.retired
            assert all(not set(protection.region) & set(other.region)
                       for other in self.protections[i + 1:])
        for byte in range(2):
            modes = [self.authority(e, byte) for e in range(3)]
            assert sum(mode == WRITE for mode in modes) <= 1
            if WRITE in modes:
                assert sum(mode != 0 for mode in modes) == 1
            assert all(mode <= self.initial[byte] for mode in modes)
        for loan in self.loans:
            if loan.pending:
                assert self.live and loan.generation == self.generation
                assert not set(loan.region) & self.retired
                if set(loan.region) & self.protected:
                    assert loan.acquisition is not None
                    acquired = self.acquisitions[loan.acquisition]
                    assert acquired.active and acquired.generation == loan.generation
                    assert (set(loan.region) & self.protected).issubset(acquired.region)
                    assert acquired.execution == loan.source or any(
                        parent.pending and parent.target == loan.source and
                        parent.acquisition == loan.acquisition and parent.mode >= loan.mode and
                        set(loan.region).issubset(parent.region) for parent in self.loans)
                else:
                    assert loan.acquisition is None
        for acquired in self.acquisitions:
            assert 0 <= acquired.protocol < len(self.protections)
            assert acquired.region == self.protections[acquired.protocol].region
            if acquired.active:
                assert self.live and acquired.generation == self.generation
                assert set(acquired.region).issubset(self.protected)
                assert not set(acquired.region) & self.retired
                assert sum(a.active and a.protocol == acquired.protocol
                           for a in self.acquisitions) == 1
        for i, owner in enumerate(self.owners):
            if not owner.active:
                continue
            assert not set(owner.payload) & self.retired
            assert all(not set(region) & self.retired for region, _ in owner.cleanup)
            assert all(self.residence[b] == owner.holder for b in owner.payload)
            assert all(not other.active or not set(owner.payload) & set(other.payload)
                       for other in self.owners[i + 1:])


@dataclass(frozen=True)
class StorageObservation:
    # Alternatives are possible physical regions, not lifetime roots or owner
    # names. The oracle below knows their concrete bytes in this finite model.
    alternatives: tuple[tuple[int, ...], ...]
    generation: int

    def access(self, state, execution, mode, *, guard=None):
        if not self.alternatives:
            raise Denied("missing physical membership is not an empty footprint")
        for region in self.alternatives:
            state.access(execution, region, mode, self.generation, guard=guard)

    def erase_in_frame(self, live_allocation_bytes):
        # The frame is an oracle for allocation identities already live when
        # the sealed value is published, not a timestamp on its container.
        # A later fresh lexical allocation is outside this upper bound.
        if not self.alternatives or any(not set(region).issubset(live_allocation_bytes)
                                        for region in self.alternatives):
            raise Denied("physical observation cannot claim an earlier frame")
        return StorageObservation((tuple(sorted(live_allocation_bytes)),), self.generation)

    def erase_with(self, other):
        if self.generation != other.generation:
            raise Denied("observation generations cannot be silently unified")
        return StorageObservation(tuple(sorted(set(self.alternatives + other.alternatives))), self.generation)


@dataclass(frozen=True)
class AuthenticatedExtent:
    # This is an oracle-supplied acquisition/containment hypothesis, not a
    # compiler rule that can be asserted by constructing a nominal owner.
    bytes: tuple[int, ...]
    generation: int

    def select(self, offset, size):
        if offset < 0 or size < 0 or offset > len(self.bytes) or size > len(self.bytes) - offset:
            raise Denied("selection exceeds authenticated physical extent")
        return StorageObservation((self.bytes[offset:offset + size],), self.generation)


@dataclass(frozen=True)
class CapturedValue:
    # The tag is the complete stored type, not its concrete Virtual provider.
    # Regions are associated-member observations, not the containing slot.
    tag: int
    regions: tuple[StorageObservation, ...]

    def join(self, other):
        if self.tag != other.tag or len(self.regions) != len(other.regions):
            raise Denied("incompatible stored value interfaces")
        return CapturedValue(self.tag, tuple(a.erase_with(b)
                                            for a, b in zip(self.regions, other.regions)))

    def call(self, state, execution, member, mode, *, guard=None):
        if not 0 <= member < len(self.regions):
            raise Denied("missing associated region is not an empty footprint")
        self.regions[member].access(state, execution, mode, guard=guard)


@dataclass(frozen=True)
class OpaqueContents:
    # One joined reference value per complete stored type, not one entry per
    # insertion. No ownership, occupancy, extraction or slot reconstruction.
    values: tuple[CapturedValue, ...] | None = None

    @classmethod
    def empty(cls):
        # Oracle: an audited transition has established no retained values.
        # This is not inferred from the age, type or absence of recorded writes.
        return cls(())

    def insert(self, value):
        if self.values is None:
            return self
        for i, previous in enumerate(self.values):
            if previous.tag == value.tag:
                return OpaqueContents(self.values[:i] + (previous.join(value),) + self.values[i + 1:])
        return OpaqueContents(self.values + (value,))

    def join(self, other):
        if self.values is None or other.values is None:
            return OpaqueContents()
        result = self
        for value in other.values:
            result = result.insert(value)
        return result

    def select_unknown(self, tag):
        if self.values is None:
            raise Denied("unknown contents do not provide complete value observations")
        for value in self.values:
            if value.tag == tag:
                return value
        raise Denied("no value evidence for the requested stored type")


@dataclass(frozen=True)
class CapturedSelection:
    # A caller-relative result recipe, not a region or an authority token.
    input: int
    tag: int

    def substitute(self, inputs):
        if not 0 <= self.input < len(inputs):
            raise Denied("missing opaque input substitution")
        return CapturedSelection(inputs[self.input], self.tag)

    def load(self, arguments, state):
        if not 0 <= self.input < len(arguments):
            raise Denied("missing opaque argument")
        slot, contents = arguments[self.input]
        # A method's no_access promise cannot authorize loading its handle.
        slot.access(state, 0, READ)
        return contents.select_unknown(self.tag)


def opaque_recipe_experiments():
    left = StorageObservation(((0,),), 0)
    right = StorageObservation(((1,),), 0)
    captured_left = CapturedValue(0, (left,))
    captured_right = CapturedValue(0, (right,))
    arguments = ((right, OpaqueContents.empty().insert(captured_left)),
                 (right, OpaqueContents.empty().insert(captured_right)))
    writer = State().lend(0, 1, (0,), WRITE)
    first = CapturedSelection(0, 0)
    # Loading an independent slot succeeds but does not authorize the capture.
    loaded = first.load(arguments, writer)
    denied(lambda: loaded.call(writer, 0, 0, READ))
    loaded.call(writer.complete(0), 0, 0, READ)
    # A wrapper's parameter positions cannot replace caller resource identity.
    second = first.substitute((1,))
    second.load(arguments, writer).call(writer, 0, 0, WRITE)
    aliased = (arguments[0], arguments[0])
    denied(lambda: second.load(aliased, writer).call(writer, 0, 0, READ))
    # Even a no_access operation still needs authority over the handle slot.
    blocked_slot = ((left, OpaqueContents.empty().insert(captured_right)),)
    denied(lambda: first.load(blocked_slot, writer))
    denied(lambda: CapturedSelection(0, 1).load(arguments, State()))
    denied(lambda: CapturedSelection(2, 0).load(arguments, State()))
    denied(lambda: first.substitute(()))
    # A returned value is instantiated once. Resolving its recipe again after
    # replacement would silently change the region denoted by the copied value.
    copied = first.load(arguments, State())
    replaced_arguments = ((right, OpaqueContents.empty().insert(captured_right)), arguments[1])
    first.load(replaced_arguments, writer).call(writer, 0, 0, READ)
    denied(lambda: copied.call(writer, 0, 0, READ))


def opaque_capture_experiments():
    observations = tuple(StorageObservation((r,), 0) for r in REGIONS)
    values = tuple(CapturedValue(0, members) for members in product(observations, repeat=2))
    checked = 0
    for first, inserted, region, loan_mode, mode, member in product(
            values, values, REGIONS, (READ, WRITE), (READ, WRITE), range(2)):
        state = State().lend(0, 1, region, loan_mode)
        contents = OpaqueContents.empty().insert(first).insert(inserted)
        abstract = contents.select_unknown(0)
        exact_accepts = True
        for alternative in (first, inserted):
            try:
                alternative.call(state, 0, member, mode)
            except Denied:
                exact_accepts = False
        try:
            abstract.call(state, 0, member, mode)
        except Denied:
            assert not exact_accepts
        else:
            assert exact_accepts
        checked += 1

    old = CapturedValue(0, (observations[1],))
    later = CapturedValue(0, (observations[0],))
    contents = OpaqueContents.empty().insert(old)
    copied = contents.select_unknown(0)
    pending = State().lend(0, 1, (0,), WRITE)
    copied.call(pending, 0, 0, READ)
    contents = contents.insert(later)
    assert contents == contents.insert(old).insert(later)
    assert contents == OpaqueContents.empty().insert(later).insert(old)
    denied(lambda: contents.select_unknown(0).call(pending, 0, 0, READ))
    # Unknown is distinct from verified empty. A known insertion cannot
    # certify the remainder of unknown storage or erase an unknown branch.
    unknown = OpaqueContents()
    assert unknown.insert(old) == unknown
    denied(lambda: unknown.select_unknown(0))
    known = OpaqueContents.empty().insert(old)
    assert known.join(OpaqueContents.empty()) == known
    assert known.join(unknown) == unknown.join(known) == unknown
    assert known.join(known) == known
    denied(lambda: known.join(unknown).select_unknown(0))
    # Missing captured facts do not forbid a no_access method when the handle
    # slot read itself is independently authorized. No member query is needed.
    StorageObservation(((1,),), 0).access(pending, 0, READ)
    # A copied old handle does not become a selection of newly inserted values.
    copied.call(pending, 0, 0, READ)
    contents.select_unknown(0).call(pending.complete(0), 0, 0, READ)
    # Associated names retain distinct footprints; neither covers its sibling.
    distinct = CapturedValue(0, (observations[0], observations[1]))
    denied(lambda: distinct.call(pending, 0, 0, READ))
    distinct.call(pending, 0, 1, WRITE)
    denied(lambda: CapturedValue(0, ()).call(State(), 0, 0, READ))
    denied(lambda: OpaqueContents.empty().select_unknown(0))
    denied(lambda: contents.select_unknown(1))
    assert contents.insert(CapturedValue(1, (observations[2],))).select_unknown(0) == contents.select_unknown(0)
    # Losing a generation is not an admissible union of valid alternatives.
    stale = CapturedValue(0, (StorageObservation(((0,),), 1),))
    denied(lambda: old.join(stale))
    return checked


@dataclass(frozen=True)
class PhysicalAllocation:
    identity: int
    address: int
    size: int
    live: bool = True


@dataclass(frozen=True)
class PhysicalView:
    backing: int
    offset: int
    size: int
    owner: int
    generation: int


@dataclass(frozen=True)
class PhysicalFrame:
    backings: frozenset[int]

    def erase_view(self, heap, view):
        # A frame bounds possible backing; it is not a substitute for validating
        # the view's live owner and physical extent before publishing evidence.
        heap.extent(view)
        if view.backing not in self.backings:
            raise Denied("view backing is outside its claimed publication frame")
        return self

    def may_overlap(self, heap, view):
        heap.extent(view)
        return view.size != 0 and view.backing in self.backings


@dataclass(frozen=True)
class PhysicalHeap:
    # Audited allocation is an oracle here. View identity, allocation identity
    # and owner-generation identity are deliberately different namespaces.
    allocations: tuple[PhysicalAllocation, ...] = ()
    owner_generations: tuple[int, ...] = (0, 0)

    def allocate(self, address, size):
        if address < 0 or size < 0:
            raise Denied("invalid physical extent")
        if any(a.live and max(a.address, address) < min(a.address + a.size, address + size)
               for a in self.allocations):
            raise Denied("fresh acquisition overlaps live physical storage")
        allocation = PhysicalAllocation(len(self.allocations), address, size)
        return replace(self, allocations=self.allocations + (allocation,)), allocation.identity

    def observe(self, backing, offset, size, owner):
        if not 0 <= backing < len(self.allocations) or not 0 <= owner < len(self.owner_generations):
            raise Denied("unknown physical backing or validity owner")
        a = self.allocations[backing]
        if not a.live or offset < 0 or size < 0 or offset > a.size or size > a.size - offset:
            raise Denied("view outside live backing")
        return PhysicalView(backing, offset, size, owner, self.owner_generations[owner])

    def extent(self, view):
        current = self.observe(view.backing, view.offset, view.size, view.owner)
        if current.generation != view.generation:
            raise Denied("expired owner observation")
        a = self.allocations[view.backing]
        return a.address + view.offset, a.address + view.offset + view.size

    def subview(self, view, offset, size):
        self.extent(view)
        if offset < 0 or size < 0 or offset > view.size or size > view.size - offset:
            raise Denied("subview enlarges its authenticated parent")
        return replace(view, offset=view.offset + offset, size=size)

    def overlap(self, left, right):
        a, b = self.extent(left), self.extent(right)
        return max(a[0], b[0]) < min(a[1], b[1])

    def invalidate_owner(self, owner):
        return replace(self, owner_generations=tuple(g + (i == owner)
                                                     for i, g in enumerate(self.owner_generations)))

    def release(self, backing):
        if not 0 <= backing < len(self.allocations) or not self.allocations[backing].live:
            raise Denied("backing has already been released")
        return replace(self, allocations=tuple(replace(a, live=False) if a.identity == backing else a
                                               for a in self.allocations))


@dataclass(frozen=True)
class PhysicalLoans:
    # Bridge the two existing finite experiments, not a third permission model.
    # Physical addresses are restricted to State's two byte coordinates here.
    heap: PhysicalHeap
    authority: State = State()
    observations: tuple[PhysicalView, ...] = ()

    def region(self, view):
        start, end = self.heap.extent(view)
        if not 0 <= start <= end <= len(self.authority.initial):
            raise Denied("physical extent outside bounded authority experiment")
        return tuple(range(start, end))

    def access(self, execution, view, mode):
        self.authority.access(execution, self.region(view), mode)

    def lend(self, source, target, view, mode):
        authority = self.authority.lend(source, target, self.region(view), mode)
        return replace(self, authority=authority, observations=self.observations + (view,))

    def complete(self, receipt, *, quiescent=True, published=True):
        if not 0 <= receipt < len(self.observations):
            raise Denied("unknown physical loan receipt")
        self.heap.extent(self.observations[receipt])
        return replace(self, authority=self.authority.complete(
            receipt, quiescent=quiescent, published=published))

    def invalidate_owner(self, owner):
        # Ending an observation is not freeing its backing or writing its bytes.
        # A byte footprint alone misses retained zero-sized observations.
        if any(loan.pending and view.owner == owner
               for loan, view in zip(self.authority.loans, self.observations)):
            raise Denied("outstanding loan retains this owner generation")
        return replace(self, heap=self.heap.invalidate_owner(owner))

    def release(self, execution, backing):
        if not 0 <= backing < len(self.heap.allocations):
            raise Denied("unknown physical backing")
        if any(loan.pending and view.backing == backing
               for loan, view in zip(self.authority.loans, self.observations)):
            raise Denied("outstanding observation retains physical backing")
        allocation = self.heap.allocations[backing]
        if not 0 <= allocation.address <= allocation.address + allocation.size <= len(self.authority.initial):
            raise Denied("physical extent outside bounded authority experiment")
        self.authority.access(execution, tuple(range(allocation.address,
                                                     allocation.address + allocation.size)), WRITE)
        # As in PhysicalHeap, matching release responsibility is an assumption;
        # this bridge adds outstanding-use and authority checks, not ownership.
        return replace(self, heap=self.heap.release(backing))

    def check(self):
        self.authority.check()
        assert len(self.observations) == len(self.authority.loans)
        for loan, view in zip(self.authority.loans, self.observations):
            if loan.pending:
                assert self.region(view) == loan.region


def physical_loan_experiments():
    heap, backing = PhysicalHeap().allocate(0, 2)
    views = tuple(heap.observe(backing, start, size, owner)
                  for start in range(3) for size in range(3 - start) for owner in range(2))
    checked = 0
    for borrowed, alias, loan_mode, access_mode in product(views, views, (READ, WRITE), (READ, WRITE)):
        state = PhysicalLoans(heap).lend(0, 1, borrowed, loan_mode)
        state.check()
        conflict = heap.overlap(borrowed, alias) and (loan_mode == WRITE or access_mode == WRITE)
        if conflict:
            denied(lambda: state.access(0, alias, access_mode))
        else:
            state.access(0, alias, access_mode)
        denied(lambda: state.invalidate_owner(borrowed.owner))
        denied(lambda: state.release(0, backing))
        denied(lambda: state.complete(0, published=False))
        restored = state.complete(0)
        restored.check()
        restored.access(0, alias, WRITE)
        denied(lambda: restored.complete(0))
        ended = restored.invalidate_owner(borrowed.owner)
        denied(lambda: ended.access(0, borrowed, READ))
        released = restored.release(0, backing)
        denied(lambda: released.access(0, alias, READ))
        checked += 1

    # Resetting a different descriptor's owner does not recover authority over
    # the shared bytes. The borrower still uses its own valid observation.
    borrowed = heap.observe(backing, 0, 1, 0)
    alias = heap.observe(backing, 0, 1, 1)
    state = PhysicalLoans(heap).lend(0, 1, borrowed, WRITE).invalidate_owner(1)
    renewed_alias = state.heap.observe(backing, 0, 1, 1)
    denied(lambda: state.access(0, renewed_alias, READ))
    state.access(1, borrowed, WRITE)
    state.check()
    # Bypassing the checked reset cannot be repaired by presenting completion.
    corrupted = replace(state, heap=state.heap.invalidate_owner(0))
    denied(lambda: corrupted.complete(0))

    # An unrelated backing can be released without completing this loan. Address
    # reuse there does not revive an observation of the released allocation.
    split_heap, first = PhysicalHeap().allocate(0, 1)
    split_heap, second = split_heap.allocate(1, 1)
    first_view = split_heap.observe(first, 0, 1, 0)
    second_view = split_heap.observe(second, 0, 1, 1)
    split = PhysicalLoans(split_heap).lend(0, 1, first_view, WRITE)
    split = split.release(0, second)
    reused_heap, reused = split.heap.allocate(1, 1)
    split = replace(split, heap=reused_heap)
    split.check()
    denied(lambda: split.access(0, second_view, READ))
    split.access(0, reused_heap.observe(reused, 0, 1, 1), WRITE)
    denied(lambda: split.access(0, first_view, READ))
    return checked


def physical_heap_experiments():
    heap, backing = PhysicalHeap().allocate(100, 4)
    whole = heap.observe(backing, 0, 4, 0)
    left, right = heap.subview(whole, 0, 2), heap.subview(whole, 2, 2)
    alias = heap.observe(backing, 0, 2, 1)
    assert not heap.overlap(left, right)
    assert heap.overlap(left, alias)  # Different owner roles do not separate bytes.
    denied(lambda: heap.allocate(101, 1))
    denied(lambda: heap.subview(left, 1, 2))
    reset = heap.invalidate_owner(0)
    denied(lambda: reset.extent(left))
    assert reset.extent(alias) == (100, 102)  # Backing itself remains live.
    renewed = reset.observe(backing, 0, 2, 0)
    assert reset.overlap(renewed, alias)
    # Reusing an address allocates a new identity, but never revives an old view.
    released = heap.release(backing)
    denied(lambda: released.extent(whole))
    reused, fresh = released.allocate(100, 4)
    assert fresh != backing
    denied(lambda: reused.extent(whole))
    assert reused.extent(reused.observe(fresh, 0, 4, 0)) == (100, 104)
    # A published frame is a set of live allocation identities, not addresses.
    old_frame = PhysicalFrame(frozenset(a.identity for a in heap.allocations if a.live))
    assert fresh not in old_frame.backings
    old_frame.erase_view(heap, whole)
    assert old_frame.may_overlap(heap, alias)
    new_view = reused.observe(fresh, 0, 4, 0)
    assert not old_frame.may_overlap(reused, new_view)
    denied(lambda: old_frame.erase_view(reused, new_view))
    denied(lambda: old_frame.erase_view(reused, whole))
    extended, later = heap.allocate(200, 2)
    later_view = extended.observe(later, 0, 2, 0)
    assert not old_frame.may_overlap(extended, later_view)
    denied(lambda: old_frame.erase_view(extended, later_view))
    # Inserting later storage into an old container requires widening the
    # value's frame. Neither the container's age nor its live owner suffices.
    widened = PhysicalFrame(old_frame.backings | {later})
    widened.erase_view(extended, later_view)
    assert widened.may_overlap(extended, later_view)
    views = tuple(heap.observe(backing, start, size, owner)
                  for start in range(5) for size in range(5 - start) for owner in range(2))
    checked = 0
    for a, b in product(views, repeat=2):
        physical_a = set(range(*heap.extent(a)))
        physical_b = set(range(*heap.extent(b)))
        assert heap.overlap(a, b) == bool(physical_a & physical_b)
        old_frame.erase_view(heap, a)
        if heap.overlap(a, b):
            assert old_frame.may_overlap(heap, b)
        checked += 1
    return checked


def storage_observation_experiments():
    extent = AuthenticatedExtent((0, 1), 0)
    left, right = extent.select(0, 1), extent.select(1, 1)
    uncertain = left.erase_with(right)
    writer = State().lend(0, 1, (0,), WRITE)
    right.access(writer, 0, WRITE)
    denied(lambda: left.access(writer, 0, READ))
    denied(lambda: uncertain.access(writer, 0, READ))
    # Metadata inspection and bounded selection do not acquire authority. In
    # particular, a checked address in byte zero is still unavailable to main.
    selected = extent.select(0, 1)
    assert writer.authority(0, 0) == 0
    denied(lambda: selected.access(writer, 0, WRITE))
    denied(lambda: extent.select(1, 2))
    denied(lambda: extent.select(-1, 1))
    denied(lambda: StorageObservation((), 0).access(writer, 0, READ))
    # A different receipt/owner/observation identity does not prove disjointness.
    overlapping = AuthenticatedExtent((0,), 0).select(0, 1)
    denied(lambda: overlapping.access(writer, 0, READ))
    # A no-access method body still needs its erased handle loaded from valid,
    # authorized storage. The body bound cannot authorize that preceding load.
    denied(lambda: uncertain.access(writer, 0, READ))
    # Ending the generation invalidates membership observations, even if the
    # new storage has the same physical byte coordinates.
    denied(lambda: left.access(State(generation=1), 0, READ))
    denied(lambda: left.erase_with(StorageObservation(((0,),), 1)))
    checks = 0
    states = (State(), writer, State().lend(0, 1, (0,), READ),
              State().lend(0, 1, (1,), WRITE))
    for state, precise, execution, mode in product(states, (left, right), range(3), (READ, WRITE)):
        # Erasure can lose a previously valid access but cannot create one.
        try:
            uncertain.access(state, execution, mode)
        except Denied:
            pass
        else:
            precise.access(state, execution, mode)
        checks += 1
    return checks


def sealed_storage_frame_experiments():
    old = AuthenticatedExtent((0,), 0).select(0, 1)
    later = AuthenticatedExtent((1,), 0).select(0, 1)
    published = old.erase_in_frame((0,))
    # The oracle now has a new, separate lexical allocation. Erasing an older
    # well-formed storage value cannot let it point into that future allocation.
    pending_later = State().lend(0, 1, (1,), WRITE)
    published.access(pending_later, 0, READ)
    # This is not physical freshness of the result: it can alias any old byte.
    pending_old = State().lend(0, 1, (0,), WRITE)
    denied(lambda: published.access(pending_old, 0, READ))
    old.erase_in_frame((0, 1)).access(State(), 0, WRITE)
    denied(lambda: old.erase_in_frame((0, 1)).access(pending_later, 0, READ))
    # A newly derived view inherits its backing. It does not allocate new bytes
    # or gain permission from its new observation/owner identity.
    derived = AuthenticatedExtent((0,), 0).select(0, 1)
    denied(lambda: derived.erase_in_frame((0,)).access(pending_old, 0, READ))
    # Reusing an old container's frame after inserting a later reference would
    # manufacture disjointness. Publication must inspect the value being stored.
    denied(lambda: later.erase_in_frame((0,)))
    changed = old.erase_with(later)
    denied(lambda: changed.erase_in_frame((0,)))
    denied(lambda: changed.erase_in_frame((0, 1)).access(pending_later, 0, READ))
    # Even a read-only capsule can contain a mutable resource or be copied; the
    # bound remains about allocation identity, independently of reference mode.
    assert published.erase_with(published) == published
    checks = 0
    for source, frame, state, execution, mode in product(
            (old, later), ((0,), (1,), (0, 1)),
            (State(), pending_old, pending_later), range(3), (READ, WRITE)):
        try:
            widened = source.erase_in_frame(frame)
        except Denied:
            continue
        try:
            widened.access(state, execution, mode)
        except Denied:
            pass
        else:
            source.access(state, execution, mode)
        checks += 1
    return checks


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
    split = initial.protect((0,)).protect((1,)).acquire(1, (0,)).acquire(2, (1,))
    split.check()
    split.access(1, (0,), WRITE, guard=0)
    split.access(2, (1,), WRITE, guard=1)


def protected_lending_experiments():
    """Use the same loan ledger for entry and acquisition-derived authority."""
    checked = 0
    for protected_region, region, mode in product(REGIONS, REGIONS, (READ, WRITE)):
        if not set(region).issubset(protected_region):
            continue
        held = State().protect(protected_region).acquire(0, protected_region)
        borrowed = held.lend(0, 1, region, mode, guard=0)
        ordinary = State().lend(0, 1, region, mode)
        for execution, byte in product(range(3), region):
            assert borrowed.authority(execution, byte) == ordinary.authority(execution, byte)
        borrowed.check()
        borrowed.access(1, region, mode, guard=0)
        denied(lambda: borrowed.access(1, region, mode))
        denied(lambda: borrowed.release(0, 0))
        denied(lambda: borrowed.access(0, region, WRITE, guard=0))
        if mode == READ:
            borrowed.access(0, region, READ, guard=0)
            denied(lambda: borrowed.access(1, region, WRITE, guard=0))
        else:
            denied(lambda: borrowed.access(0, region, READ, guard=0))
        for byte in set(protected_region) - set(region):
            borrowed.access(0, (byte,), WRITE, guard=0)

        # A child can re-lend the derived route, but cannot manufacture a grant
        # independent of the original acquisition or finish before descendants.
        nested = borrowed.lend(1, 2, region, mode, guard=0)
        ordinary_nested = ordinary.lend(1, 2, region, mode)
        for execution, byte in product(range(3), region):
            assert nested.authority(execution, byte) == ordinary_nested.authority(execution, byte)
        nested.check()
        nested.access(2, region, mode, guard=0)
        denied(lambda: nested.complete(0))
        denied(lambda: nested.release(0, 0))
        returned_child = nested.complete(1)
        returned_child.check()
        returned_child.access(1, region, mode, guard=0)
        denied(lambda: returned_child.release(0, 0))
        returned = returned_child.complete(0)
        returned.check()
        returned.access(0, region, WRITE, guard=0)
        released = returned.release(0, 0)
        released.check()
        assert released.generation == held.generation
        denied(lambda: released.access(1, region, mode, guard=0))
        renewed = released.acquire(0, protected_region)
        renewed.access(0, region, WRITE, guard=1)
        denied(lambda: renewed.access(0, region, READ, guard=0))
        checked += 1

    held = State().protect((0,)).acquire(0, (0,))
    readers = held.lend(0, 1, (0,), READ, guard=0).lend(0, 2, (0,), READ, guard=0)
    readers.check()
    one_left = readers.complete(0)
    one_left.access(0, (0,), READ, guard=0)
    denied(lambda: one_left.access(0, (0,), WRITE, guard=0))
    denied(lambda: one_left.release(0, 0))
    one_left.complete(1).release(0, 0).check()
    # Ordinary entry authority does not acquire a dependency on an unrelated
    # guard merely because the caller also holds that guard.
    ordinary = held.lend(0, 1, (1,), WRITE, guard=0)
    assert ordinary.loans[0].acquisition is None
    ordinary.release(0, 0).check()
    ordinary.access(1, (1,), WRITE)
    return checked


def authority_source_experiments():
    """Challenge per-access coverage without proposing production summary IR."""
    protected = State().protect((0,))
    assert protected.authority(0, 0) == 0

    def balanced_update(state):
        guard = len(state.acquisitions)
        held = state.acquire(0, (0,))
        held.access(0, (0,), WRITE, guard=guard)
        return held.release(guard, 0)

    # A logical write needs no payload grant at entry when acquisition provides
    # it. Unrelated pending loans remain intact across the balanced helper.
    borrowed = protected.lend(0, 1, (1,), WRITE)
    returned = balanced_update(balanced_update(borrowed))
    returned.check()
    assert returned.authority(0, 0) == 0
    assert returned.loans == borrowed.loans
    denied(lambda: returned.access(0, (1,), READ))
    returned.access(1, (1,), WRITE)

    held = protected.acquire(0, (0,))
    released = held.release(0, 0)
    checked = 0
    for state, active in ((protected, False), (held, True), (released, False)):
        for mode, guard in product((READ, WRITE), (None, 0)):
            if active and guard == 0:
                state.access(0, (0,), mode, guard=guard)
            else:
                denied(lambda: state.access(0, (0,), mode, guard=guard))
            checked += 1

    # Intentionally challenge the unsound summary candidate "some access to R
    # is guarded, therefore every access to R is mediated". Eight mixed paths
    # below have the same write footprint and some guarded access, yet fail.
    false_certificates = 0
    for length in range(1, 4):
        for sources in product((None, 0), repeat=length):
            for source in sources:
                if source == 0:
                    held.access(0, (0,), WRITE, guard=source)
                else:
                    denied(lambda: held.access(0, (0,), WRITE, guard=source))
            if any(source == 0 for source in sources) and not all(source == 0 for source in sources):
                false_certificates += 1
            checked += 1
    assert false_certificates == 8

    # Even holding two grants does not make the wrong acquisition-derived route
    # valid. Region/protocol correspondence must survive wrapper substitution.
    two = State().protect((0,)).protect((1,)).acquire(0, (0,)).acquire(0, (1,))
    two.access(0, (0,), WRITE, guard=0)
    two.access(0, (1,), WRITE, guard=1)
    denied(lambda: two.access(0, (1,), WRITE, guard=0))
    denied(lambda: two.access(0, (0,), WRITE, guard=1))
    return checked, false_certificates


def protected_erasure_experiments():
    """A common acquired envelope can justify access without exact targets."""
    held = State().protect((0, 1)).acquire(0, (0, 1))
    envelope = StorageObservation(((0, 1),), held.generation)
    for mode in (READ, WRITE):
        envelope.access(held, 0, mode, guard=0)
    denied(lambda: envelope.access(held, 0, READ))
    denied(lambda: StorageObservation((), 0).access(held, 0, READ, guard=0))
    denied(lambda: StorageObservation(((0,),), 1).access(held, 0, READ, guard=0))

    checked = 0
    for first, second, borrowed, loan_mode, mode in product(
            REGIONS, REGIONS, REGIONS, (READ, WRITE), (READ, WRITE)):
        state = held.lend(0, 1, borrowed, loan_mode, guard=0)
        alternatives = tuple(CapturedValue(0, (StorageObservation((region,), 0),))
                             for region in (first, second))
        abstract = alternatives[0].join(alternatives[1])
        exact_accepts = True
        for value in alternatives:
            try:
                value.call(state, 0, 0, mode, guard=0)
            except Denied:
                exact_accepts = False
        try:
            abstract.call(state, 0, 0, mode, guard=0)
        except Denied:
            assert not exact_accepts
        else:
            assert exact_accepts
        checked += 1
    # The common protocol envelope does not bypass its own derived loan.
    reader = held.lend(0, 1, (0,), READ, guard=0)
    envelope.access(reader, 0, READ, guard=0)
    denied(lambda: envelope.access(reader, 0, WRITE, guard=0))
    StorageObservation(((1,),), 0).access(reader, 0, WRITE, guard=0)
    return checked


def protocol_custody_experiments():
    """One protocol's views never manufacture independently acquirable locks."""
    checked = 0
    for protected_region, view in product(REGIONS, REGIONS):
        if not set(view).issubset(protected_region):
            continue
        protected = State().protect(protected_region)
        held = protected.acquire(1, view, protocol=0)
        held.check()
        assert held.acquisitions[0].region == protected_region
        held.access(1, protected_region, WRITE, guard=0)
        # Even a disjoint requested view of the same lock must wait.
        for other in REGIONS:
            if set(other).issubset(protected_region):
                denied(lambda: held.acquire(2, other, protocol=0))
        denied(lambda: protected.acquire(1, view, protocol=1))
        denied(lambda: protected.protect(view))
        released = held.release(0, 1)
        reacquired = released.acquire(2, view, protocol=0)
        reacquired.check()
        reacquired.access(2, view, WRITE, guard=1)
        denied(lambda: reacquired.access(2, view, WRITE, guard=0))
        checked += 1

    distinct = State().protect((0,)).protect((1,))
    both = distinct.acquire(1, (0,), protocol=0).acquire(2, (1,), protocol=1)
    both.check()
    both.access(1, (0,), WRITE, guard=0)
    both.access(2, (1,), WRITE, guard=1)
    denied(lambda: distinct.acquire(1, (1,), protocol=0))
    denied(lambda: distinct.acquire(1, (0,), protocol=1))
    denied(lambda: distinct.acquire(1, (0, 1)))
    only_second = both.release(0, 1)
    only_second.access(2, (1,), WRITE, guard=1)
    denied(lambda: only_second.access(1, (0,), WRITE, guard=0))
    # If protocol identity is erased to alternatives, every alternative must
    # satisfy the binding, not just whichever free lock is convenient.
    for candidate in (0, 1):
        if candidate == 0:
            distinct.acquire(1, (0,), protocol=candidate).check()
        else:
            denied(lambda: distinct.acquire(1, (0,), protocol=candidate))
    return checked


def owner_experiments():
    local = State().establish_owner(0, (0,))
    moved = local.handoff(0, 0, 1)
    moved.check()
    denied(lambda: moved.access(0, (0,), READ))
    moved.access(1, (0,), WRITE)
    denied(lambda: moved.cleanup_owner(0, 0))
    destroyed = moved.cleanup_owner(0, 1)
    destroyed.check()
    denied(lambda: destroyed.cleanup_owner(0, 1))
    denied(lambda: destroyed.access(1, (0,), READ))
    # Identical payload shape, different cleanup operation requirements.
    external = State().establish_owner(0, (0,), (((1,), WRITE),))
    denied(lambda: external.handoff(0, 0, 1))
    # Readonly payload sharing does not invoke the latent cleanup operation.
    shared = external.lend(0, 1, (0,), READ)
    shared.access(1, (0,), READ)
    denied(lambda: shared.cleanup_owner(0, 0))
    denied(lambda: shared.handoff(0, 0, 2))
    shared.complete(0).cleanup_owner(0, 0).check()
    # Exclusively lending the external provider permits remote cleanup while
    # keeping the payload and provider's lifetimes/responsibilities distinct.
    transferred = external.lend(0, 1, (1,), WRITE).handoff(0, 0, 1)
    transferred.check()
    denied(lambda: transferred.access(0, (1,), READ))
    returned = transferred.cleanup_owner(0, 1).complete(0)
    returned.check()
    returned.access(0, (1,), WRITE)
    denied(lambda: returned.access(0, (0,), READ))
    denied(lambda: local.establish_owner(0, (0,)))
    dependent = external.establish_owner(0, (1,))
    denied(lambda: dependent.cleanup_owner(1, 0))
    dependent.cleanup_owner(0, 0).cleanup_owner(1, 0).check()
    ended_provider = State().establish_owner(0, (1,)).cleanup_owner(0, 0)
    denied(lambda: ended_provider.establish_owner(0, (0,), (((1,), WRITE),)))
    # Erasure must check each possible destructor requirement, not just bytes.
    for candidate in (local, external):
        if candidate == external:
            denied(lambda: candidate.handoff(0, 0, 1))
        else:
            candidate.handoff(0, 0, 1).check()


def explore_interactions(depth=4):
    """Combine transitions under explicit allocation/identity bounds.

    Establishment and synchronized acquisition remain audited assumptions.
    Successful step invariants are checked rather than assuming the isolated
    examples imply safety of their combinations.
    """
    frontier = {State()}
    seen = set(frontier)
    transitions = 0
    for _ in range(depth):
        following = set()
        for state in frontier:
            actions = []
            for region in REGIONS:
                actions.append(lambda r=region: state.protect(r))
                if len(state.owners) < 2:
                    actions.append(lambda r=region: state.establish_owner(0, r))
                    actions.append(lambda r=region: state.establish_owner(0, r, (((1,), WRITE),)))
                if len(state.acquisitions) < 2:
                    for execution in range(3):
                        actions.append(lambda r=region, e=execution: state.acquire(e, r))
                if len(state.loans) < 2:
                    for source, target, mode in product(range(3), (1, 2), (READ, WRITE)):
                        actions.append(lambda r=region, a=source, b=target, m=mode: state.lend(a, b, r, m))
                    for guard, acquired in enumerate(state.acquisitions):
                        if acquired.active:
                            for target, mode in product((1, 2), (READ, WRITE)):
                                actions.append(lambda r=region, g=guard, a=acquired.execution, b=target, m=mode:
                                               state.lend(a, b, r, m, guard=g))
            for receipt in range(len(state.loans)):
                actions.append(lambda k=receipt: state.complete(k))
            for guard, acquired in enumerate(state.acquisitions):
                actions.append(lambda k=guard, e=acquired.execution: state.release(k, e))
            for index, owner in enumerate(state.owners):
                actions.append(lambda k=index, e=owner.holder: state.cleanup_owner(k, e))
                for target in range(3):
                    actions.append(lambda k=index, a=owner.holder, b=target: state.handoff(k, a, b))
            for action in actions:
                try:
                    result = action()
                except Denied:
                    continue
                try:
                    result.check()
                except AssertionError:
                    raise AssertionError(f"interaction invariant failed: {state!r} -> {result!r}") from None
                transitions += 1
                if result not in seen:
                    following.add(result)
        seen.update(following)
        frontier = following
    return len(seen), transitions


if __name__ == "__main__":
    opaque_recipe_experiments()
    opaque_captures_checked = opaque_capture_experiments()
    physical_loans_checked = physical_loan_experiments()
    physical_checked = physical_heap_experiments()
    frames_checked = sealed_storage_frame_experiments()
    observations_checked = storage_observation_experiments()
    adversarial_traces()
    owner_experiments()
    substitution_experiments()
    protected_experiments()
    protected_loans_checked = protected_lending_experiments()
    sources_checked, false_certificates = authority_source_experiments()
    protected_erasure_checked = protected_erasure_experiments()
    protocol_custody_checked = protocol_custody_experiments()
    compositions = transformer_experiments()
    summaries_checked, summaries_accepted = summary_experiments()
    states, transitions = explore()
    mixed_states, mixed_transitions = explore_interactions()
    print(f"Authority experiment: {states} states, {transitions} accepted transitions; invariants hold")
    print(f"Resource transformer experiment: {compositions} modular compositions checked")
    print(f"Completion summaries: {summaries_checked} cases checked, {summaries_accepted} accepted conservatively")
    print(f"Storage observations: {observations_checked} erasure checks and physical membership adversarial cases passed")
    print(f"Sealed storage frames: {frames_checked} conservative erasure checks and late-capture adversarial cases passed")
    print(f"Physical backing: {physical_checked} overlap checks and release/reuse adversarial cases passed")
    print(f"Physical loans: {physical_loans_checked} authority/lifetime combinations checked")
    print(f"Opaque captures: {opaque_captures_checked} typed member-region joins checked")
    print("Opaque result recipes: input substitution, slot/capture separation and snapshot contrasts passed")
    print("Ownership/latent cleanup adversarial cases passed")
    print("Receipt/region substitution adversarial cases passed")
    print("Protected-access adversarial traces passed (not included in the exhaustive loan exploration)")
    print(f"Acquisition-derived lending: {protected_loans_checked} region/mode combinations and nested/reader contrasts passed")
    print(f"Authority sources: {sources_checked} coverage cases; {false_certificates} false region-wide certificates rejected")
    print(f"Protected abstraction: {protected_erasure_checked} exact/erased coverage comparisons passed")
    print(f"Protocol custody: {protocol_custody_checked} payload/view combinations and wrong-instance contrasts passed")
    print(f"Combined transitions: {mixed_states} states, {mixed_transitions} accepted steps at depth four")
    print("Scope: two bytes, three executions, at most two loans; loan depth five and combined depth four; not a soundness proof")
