Owner: Type = (.value: Int32)
implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () {})
Borrower: Type = (.owner: $&Owner)
implement Deinit#(Borrower) (
    .deinit = (.self: $&Borrower) -> () { deinit(.self = self&.owner) }
)
main := () -> () {
    owner ::= Owner(1)
    borrower ::= Borrower($&owner)
}
