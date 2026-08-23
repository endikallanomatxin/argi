Resource : Type = (
    .value: Int32
)

Holder : Type = (
    .owned: $&Resource
    .borrowed: $&Resource
)

release(.self: $$&Holder) -> () #invalidates_dependency(self, owned) := {}

read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    owned :: Resource = (.value = 1)
    borrowed :: Resource = (.value = 2)
    holder :: Holder = (.owned = $&owned, .borrowed = $&borrowed)
    pointer : &Resource = holder.borrowed

    release(.self = $$&holder)
    read(.value = pointer)
    status_code = 0
}
