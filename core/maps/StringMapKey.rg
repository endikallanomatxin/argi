StringMapKey#(.Key: Type): Contract = (
    .key_view: (.key: Key) -> (.view: StringView)
)
implement StringMapKey#(StringView) (
    .key_view = (.key: StringView) -> (.view: StringView) { view = key }
)
string_hash_map_key_view#(.Key: Type: StringMapKey#(Key)) := (.key: Key) -> (.view: StringView) {
    view = StringMapKey#(Key).key_view(.key = key)
}
