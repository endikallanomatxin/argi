# Core library usability

## Design and implementation order

1. Add checked unsigned endian reads and writes over initialized byte views.
   Validate complete ranges before writes; use arithmetic instead of native
   layout casts. Add a borrowed cursor with transactional position updates.
2. Add value and borrowed Deque iteration in logical order. Retain the ring
   shape dependency in iterators so structural mutation rejects stale cursors.
3. Add bounded stream helpers and readonly block writing. Preserve partial
   progress semantics and distinguish unexpected EOF and size-limit failures.
4. Extend filesystem operations through shared native adapters: directory
   creation/enumeration, metadata, seek/truncate, and securely created temporary
   storage. Preserve capability dependencies and private native ownership.
5. Refresh the core inventory and active release plans after validation.

These library changes normally affect no tokenizing, syntaxing, semantizing,
or codegen APIs. Any compiler limitation encountered must receive a focused
regression case before extending compiler behavior. Keep each implementation
unit, its tests, and its contracts in one commit.

Owning generic maps, Unicode decoding, numeric utilities, process extensions,
and richer testing diagnostics remain subsequent independent work candidates.
