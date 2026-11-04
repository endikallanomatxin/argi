CounterAccess#(.Provider: Type): Contract = (
    domain state
    .get: (.self: &Provider) -> (.result: Int32) where { reads(self.state) }
    .set: (.self: &Provider) -> () where { writes(self.state) }
)
Provider := (._counter: $&Int32)
implement CounterAccess#(Provider) (
    .get = (.self: &Provider) -> (.result: Int32) { result = self&._counter& }
    .set = (.self: &Provider) -> () { self&._counter& = 42 }
) where { state(self._counter) }
make := (.provider: &Provider) -> (.counter: Virtual#(CounterAccess)) {
    counter = to_virtual#(CounterAccess)(provider)
}
get := (.counter: Virtual#(CounterAccess)) -> (.result: Int32) {
    result = CounterAccess#().get(.self = &counter)
}
set := (.counter: Virtual#(CounterAccess)) -> () {
    CounterAccess#().set(.self = &counter)
}
read_provider := (.provider: &Provider) -> (.result: Int32) {
    counter ::= to_virtual#(CounterAccess)(provider)
    result = CounterAccess#().get(.self = &counter)
}
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&executor_provider)
    value :: Int32 = 7
    provider: Provider = (._counter = $&value)
    counter ::= make(.provider = &provider)
    copied ::= counter
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    if get(.counter = copied) != 7 { abort }
    if read_provider(.provider = &provider) != 7 { abort }
    if unwrap_or_abort(.value = await($&future)) != 7 { abort }
    set(.counter = counter)
    if value != 42 { abort }
}
