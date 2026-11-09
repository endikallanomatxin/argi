Reader#(.T: Type): Contract = (
    .state: Region#(T)
    .read: (.self: &T) -> (.result: Int32) where reads(self.state)
)
Provider := (.first: &Int32, .second: &Int32)
implement Reader#(Provider) (
    .state = region(self.first, self.second),
    .read = (.self: &Provider) -> (.result: Int32 = 0) {
        cursor :: &Int32 = self&.first
        index :: UIntNative = 0
        while index < 2 {
            result = result + cursor&
            cursor = self&.second
            index = index + 1
        }
    }
)
main := () -> () {
    first :: Int32 = 21
    second :: Int32 = 9
    provider ::= Provider(&first, &second)
    reader ::= Virtual#(Reader)(&provider)
    if read(&reader) != 42 { abort }
}
