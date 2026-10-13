Releaser: Abstract = (
    release(.self: $&Self) -> () where consumes(self)
)

Manager: Type = (.unused: Int32)

Manager implements Releaser

implement Deinit#(Manager) (
    .deinit = (.self: $&Manager) -> () {

    }
)

release(.self: $&Manager) -> () := { deinit(self) }

main() -> () := {
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)($&manager)
}
