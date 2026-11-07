Counter#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .get: (.self: &Provider) -> (.result: Int32) where reads(self.state)
    .set: (.self: &Provider) -> () where writes(self.state)
)
CounterProvider := (.value: $&Int32)
implement Counter#(CounterProvider) (
    .state = region(self.value),
    .get = (.self: &CounterProvider) -> (.result: Int32) { result = self&.value& },
    .set = (.self: &CounterProvider) -> () { self&.value& = 42 }
)
OtherCounterProvider := (.tag: UInt8, .value: $&Int32)
implement Counter#(OtherCounterProvider) (
    .state = region(self.value),
    .get = (.self: &OtherCounterProvider) -> (.result: Int32) { result = self&.value& },
    .set = (.self: &OtherCounterProvider) -> () { self&.value& = 42 }
)
Holder := (.counter: Virtual#(Counter))
read := (.value: &Int32) -> (.result: Int32) { result = value& }
use := (.array: &DynamicArray#(Holder), .index: UIntNative, .value: &Int32, .executor: Virtual#(Executor)) -> () {
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = value), .executor = executor))
    holder ::= unwrap_or_abort(.value = get_reference(.self = array, .index = index))
    Counter#().set(&holder&.counter)
    _ = unwrap_or_abort(.value = await($&future))
}
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&executor_provider)
    allocator_provider ::= CAllocator(.ffi = system.ffi)
    assume allocator ::= Virtual#(Allocator)($&allocator_provider)
    first :: Int32 = 7
    second :: Int32 = 9
    first_provider: CounterProvider = (.value = $&first)
    second_provider: OtherCounterProvider = (.tag = 1, .value = $&second)
    array ::= unwrap_or_abort(.value = DynamicArray#(Holder)(.capacity = 2))
    push_assume_capacity(.self = $&array, .value = Holder(Virtual#(Counter)(&first_provider)))
    push_assume_capacity(.self = $&array, .value = Holder(Virtual#(Counter)(&second_provider)))
    use(.array = &array, .index = 1, .value = &second, .executor = executor)
}
