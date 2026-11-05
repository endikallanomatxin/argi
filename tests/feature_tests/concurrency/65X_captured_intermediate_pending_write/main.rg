CounterAccess#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .get: (.self: &Provider) -> (.result: Int32) where { reads(self.state) }
    .set: (.self: &Provider) -> () where { writes(self.state) }
)
Holder := (.counter: $&Int32)
Provider := (._holder: &Holder)
implement CounterAccess#(Provider) (
    .state = region(self._holder.counter),
    .get = (.self: &Provider) -> (.result: Int32) { result = self&._holder&.counter& }
    .set = (.self: &Provider) -> () { self&._holder&.counter& = 42 }
)
forward := (.counter: Virtual#(CounterAccess)) -> (.result: Virtual#(CounterAccess)) { result = counter }
get := (.counter: Virtual#(CounterAccess)) -> (.result: Int32) {
    result = CounterAccess#().get(.self = &counter)
}
set := (.counter: Virtual#(CounterAccess)) -> () {
    CounterAccess#().set(.self = &counter)
}
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&executor_provider)
    value :: Int32 = 7
    holder: Holder = (.counter = $&value)
    provider: Provider = (._holder = &holder)
    counter ::= to_virtual#(CounterAccess)(&provider)
    copied ::= forward(.counter = counter)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    set(.counter = copied)
    if unwrap_or_abort(.value = await($&future)) != 7 { abort }
    set(.counter = counter)
    if value != 42 { abort }
}
