-- Comparisons borrow elements so ordering never consumes their resources.
BorrowedOrderPolicy#(.Policy: Type, .t: Type): Contract = (
    .less : (.self: &Policy, .left: &t, .right: &t) -> (.ok: Bool)
)
