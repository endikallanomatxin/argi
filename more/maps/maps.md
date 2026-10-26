# Maps

Core provides `HashMap<.key: Key, .value: Value>` and `HashSet<.key: Key>`.
Both use `StandardHashPolicy` by default and accept custom policies.

Use `String` for owning text keys and `StringView` for borrowed text keys.
Both accept `StringView` queries. Borrowed key storage must remain live and
unchanged while stored.

See [collection contracts](../../description/169_other_collections.md) for
construction, lookup, iteration, and allocation-error handling.
