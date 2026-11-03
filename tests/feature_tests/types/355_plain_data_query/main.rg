Record := (.value: Int32, .flag: Bool)
Choice := (..none, ..some(.value: Int32))
Borrowed := (.value: &Int32)
Owner := (.value: Int32)
implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () { _ = self })
ContainsOwner := (.owner: Owner)
Callback(.value: CInt) -> (.result: CInt): CFunctionPointer
check := #(.T: Type) () -> (.result: Bool) { result = is_plain_data(.type = T) }
known ::= #run () -> (.result: Bool) { result = check#(Record)() }
main := () -> () {
    if is_plain_data(.type = Int32) {} else { abort }
    if is_plain_data(.type = Array#(.n = 2, .t: Record)) {} else { abort }
    if is_plain_data(.type = Choice) {} else { abort }
    if known {} else { abort }
    if is_plain_data(.type = Borrowed) { abort }
    if is_plain_data(.type = Owner) { abort }
    if is_plain_data(.type = ContainsOwner) { abort }
    if is_plain_data(.type = RawPointer#(.t: Int32)) { abort }
    if is_plain_data(.type = Callback) { abort }
}
