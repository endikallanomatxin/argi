# Contract capabilities

[Contracts and conformance](135_contracts.md) replaces the former abstract-type
model. `Abstract`, `implements`, `satisfies`, implicit `Self`, and `defaultsto`
are rejected with migration diagnostics.

Declare named participants and operation members, then provide their operations
through an explicit implementation:

```rg
Animal#(.Value: Type): Contract = (
    .speak: (.who: &Value) -> (.sound: Int32)
)
Dog: Type = (.voice: Int32)
implement Animal#(Dog) (
    .speak = (.who: &Dog) -> (.sound: Int32) { sound = who&.voice }
)

listen#(.Value: Type: Animal#(Value))(.who: &Value) -> (.sound: Int32) := {
    sound = Animal#(Value).speak(who)
}
```

A contract has no runtime representation. Store a concrete type, declare an
explicitly constrained compile-time parameter, or request a borrowed virtual
handle with `Virtual#(.contract: Animal)`. See [Virtual types](134_virtual_types.md).

Participants select the most specific applicable implementation. Its associated
types and constants are resolved afterwards; they never infer missing participants
from an expected output. Composition preserves dependency operation identities.
See [Contract dispatch](131_multiple_dispatch.md) for selection and coherence.

The bundled collection contracts include Indexable, IndexableMutable,
IndexableValue, Resizable and Removable. Their implementations select collection
and provider types explicitly. MatrixShape associates element types and dimensions;
MatrixProduct relates two operands and specializes its result representation.
See [Lists](161_lists.md) and the official matrix library for concrete examples.
