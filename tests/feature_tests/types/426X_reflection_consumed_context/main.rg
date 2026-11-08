Owner := (.drops: $&Int32)

implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () { self&.drops&= self&.drops&+ 1 })

Pair := (.first: Owner, .second: Owner)

field := #(.T: Type) (.name: StringView, .context: Owner) -> (.result: T) { result = ~context }

main := () -> () {
    drops :: Int32 = 0
    owner ::= Owner(.drops = $&drops)
    pair ::= construct_record#(Pair, field)(.context = ~owner)
}
