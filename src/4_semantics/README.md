# Semantizing Notes

## Type equality / compatibility

- `typesExactlyEqual`: strict type identity. Nominal declarations must be the same declaration or have the same generic identity; generic identities must match exactly.
- `typesStructurallyEqual`: structural equality used in specific semantizing/codegen contexts where matching shape is intended, such as anonymous or inferred structural forms.
- `typesCompatible`: assignment and argument-passing compatibility. This is the default check for whether an expression can be used where another type is expected.
- `choiceTypeIsSupersetOf`: inclusion relation for choice types. The expected choice accepts the actual choice when it contains every actual variant.
- Generic identity: stable identity for instantiated generic structs, choices, and arrays. Use it when nominal equality should survive separate instantiation paths, not as a broad structural fallback.
