# Contract dispatch

Dispatch is scoped to an operation identity declared by a contract. Ordinary
functions have one identity per module namespace and may be generic, but do
not define overload families. See [contracts](135_contracts.md) for declaration
and implementation syntax.

## Selecting an operation and an implementation

An unqualified call first identifies applicable operations from visible contracts.
If operations from different contracts are applicable, the caller must qualify
its intended identity. A more specific implementation in another contract never
resolves that ambiguity.

Once the operation identity is known, the compiler selects the most specific
applicable implementation for the contract's complete participant tuple. Generic
patterns can specialize closed types and nominal applications, including their
compile-time type and integer arguments. Equivalent implementation patterns are
rejected; incomparable maximal candidates are ambiguous.

## Participants and outputs

Participants are compile-time inputs to contract selection. They need not all
appear in an operation's runtime inputs. For example, Convert's Source describes
the value being converted, while Target describes the requested destination.
Target can select an implementation even though it appears only in the operation's
result. This is more general than dispatch based solely on runtime argument types.

Associated types and constants are determined by the selected implementation.
An associated Result never ranks candidates or supplies missing participant
bindings through arbitrary reverse inference. Input patterns and explicitly
supplied participants establish selection before associated results are resolved.

## Constructors and destruction

A call to `T(...)` supplies T and infers its Args record, then selects the most
specific applicable `Init#(T, Args)` implementation. The associated Result is
validated after selection. Structural construction remains available without Init.

Explicit destruction and automatic cleanup use the same selected `Deinit#(T)`
evidence. Ordinary functions named `deinit` retain ordinary call effects and do
not establish cleanup obligations. Neither lifecycle operation has a separate
nominal family registry or global overload fallback.

## Migration status

Init and Deinit use contract dispatch throughout bundled core, official more and
compiler fixtures. Their former declaration syntax is rejected. Older ordinary
function and operator overload declarations still have compatibility routes
while their consumers migrate. Convert now selects scoped contract evidence,
including generic and specialized implementations; numeric type-call conversions
are rejected in favor of explicit convert calls. Operator migration will use an
Args participant to retain static dispatch for additional capabilities, as
described in [contracts](135_contracts.md).
