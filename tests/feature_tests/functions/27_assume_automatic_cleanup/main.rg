drops :: Int32 = 0

Tracked: Type = ()

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked, .amount: Int32 = 1) -> () {
        drops = drops + amount
    }
)

main := () -> (.status_code: Int32 = 0) {
    assume amount: Int32 = 3
    if true { tracked ::= Tracked() }
    if drops != 3 { status_code = 1 }
}
