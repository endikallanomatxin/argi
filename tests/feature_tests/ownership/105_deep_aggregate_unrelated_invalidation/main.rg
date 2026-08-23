Resource : Type = (.value: Int32)
L1 : Type = (.next: &Resource)
L2 : Type = (.next: L1)
L3 : Type = (.next: L2)
L4 : Type = (.next: L3)
L5 : Type = (.next: L4)
L6 : Type = (.next: L5)
L7 : Type = (.next: L6)
L8 : Type = (.next: L7)
L9 : Type = (.next: L8)
L10 : Type = (.next: L9)

extract(.value: L10) -> (.pointer: &Resource) := {
    pointer = value.next.next.next.next.next.next.next.next.next.next
}

deinit(.self: $$&Resource) -> () #invalidates(self) := {}
read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 1)
    unrelated :: Resource = (.value = 2)
    nested :: L10 = (.next = (.next = (.next = (.next = (.next = (.next = (.next = (.next = (.next = (.next = &resource))))))))))
    pointer ::= extract(.value = nested)
    deinit(.self = $$&unrelated)
    read(.value = pointer)
    status_code = 0
}
