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

A call to `T(...)` selects the most specific `Init#(T)` implementation for its
target, then infers operation-local parameters from the selected init signature.
Inputs can infer missing target parameters; different inferred targets require
explicit disambiguation. The result is checked after selection and never supplies
missing participant bindings. Structural construction remains available without Init.

Explicit destruction and automatic cleanup use the same selected `Deinit#(T)`
evidence. Ordinary functions named `deinit` retain ordinary call effects and do
not establish cleanup obligations. Neither lifecycle operation has a separate
nominal family registry or global overload fallback.

## Migration status

Init, Deinit and Convert use contract dispatch throughout bundled core, official
more and compiler fixtures. Their former declaration syntax and numeric type-call
conversions are rejected. Custom addition and equality use Add and Equal with an
Args participant to retain static dispatch for auxiliary capabilities. The !=
symbol negates the selected Equal operation, never selecting a second identity.
Legacy operator declarations, their metadata and global selectors are removed.

Arithmetic symbols select Add, Subtract, Multiply, Divide or Remainder evidence.
Bundled scalar implementations then lower to representation primitives, preserving
constant expressions without an ordinary-function fallback. Custom implementations
retain ordinary selected calls and can provide different associated results.

Scalar equality, including Bool, UnicodeScalar and RawPointer, selects Equal evidence.
C enum and C function-pointer equality also select Equal evidence. Ordered
comparisons use CompareRelations#(Left, Right), with four Bool predicates. Its
generic implementation derives the predicates from Compare#(Left, Right).
More specific implementations can replace those algorithms. Ordering has no Args
participant. Native predicates lower only after evidence selection; see
[contracts](135_contracts.md).
The official matrix library uses shape evidence and MatrixProduct specialization
through standard Multiply adapters, including a diagonal result representation.
