Pair := (.left: Int32, .right: Int32)

update := (.value: $&Pair) -> () { value&.left = 40 }

read := (.value: &Int32) -> (.result: Int32) { result = value&}

borrow := (.value: &Int32) -> (.result: &Int32) { result = value }

main := () -> (.status_code: Int32 = 0) {
    pairs :: [2]Pair = ((.left = 1, .right = 2), (.left = 3, .right = 4))
    saved ::= pairs
    index :: UIntNative = 0
    reference ::= $&pairs[index]
    index = 1
    update(.value = reference)
    if saved[0].left != 1 or pairs[1].left != 3 { abort }
    left ::= read(.value = $&pairs[0].left)
    right ::= borrow(.value = &pairs[0].right)
    status_code = left + right&
}
