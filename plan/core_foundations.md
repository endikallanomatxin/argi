# Standard-library foundations

Implement reusable foundations before application libraries. Preserve explicit
allocation, capabilities, ownership and nominal errors throughout.

## Development order

1. Collections: extend owner-aware algorithms beyond DynamicArray; audit
   remaining containers under structural cleanup and allocation failures.
2. Streams: audit bounded adapters under allocation and native read failures;
   compose consumers through owning line iteration.
3. Filesystem/tools: argument relationships, subcommands and richer typed
   CLI diagnostics; audit traversal under filesystem changes and resource limits.
4. Numeric/time foundations: broader math coverage and timezone-aware date
   formats, preserving explicit domain and range contracts.
5. More: JSON tree/typed consumers and streaming CSV inputs, then
   compression/archive consumers. Borrowed JSON tokens and owning CSV records
   remain the allocation-aware foundations for those consumers.
6. Services/runtime: HTTP and selected hashes/crypto; additional atomic widths,
   native threads and synchronization require the transfer contracts in 0.5.
   Integrate cooperative cancellation/deadlines with task and native-wait cleanup.

## Compiler dependencies

Generic bodies still need contextual choice-literal resolution inside constructor
fields and binary operands, and standalone lexical blocks. Use explicit typed
bindings until that path carries the expected nominal types into specialization.
Failed specializations should explain the body failure rather than only listing
overload signatures.

Contextual positional record assignments still need their nominal destination
carried through codegen; use constructors or named fields in those assignments.
Generic consumers such as `unwrap_or_abort` also need inferred error envelopes
to retain the nominal Errable identity; direct matching remains available.
Positional `ArrayView#(UInt8)` annotations also need their generic identity
normalized against named core specializations; keep `.t: UInt8` in those
annotations until they interoperate with `length` and view operations.

Each unit includes executable or negative feature tests and public contracts.
Use application usecases to validate composition. Existing implementations must
be audited before adding parallel APIs; empty sketches do not count as support.
Library-only foundations use existing tokenizing, syntaxing, semantizing and
codegen constructs. Compiler work is justified by a concrete failing consumer.
