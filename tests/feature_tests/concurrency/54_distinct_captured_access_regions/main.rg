CounterAccess#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .set: (.self: &Provider) -> () where { writes(self.state) }
)
Provider := (._counter: $&Int32)
implement CounterAccess#(Provider) (
    .state = region(self._counter),
    .set = (.self: &Provider) -> () { self&._counter& = 42 }
)
set := (.counter: Virtual#(CounterAccess)) -> () { CounterAccess#().set(.self = &counter) }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&executor_provider)
    value :: Int32 = 7
    other :: Int32 = 0
    provider: Provider = (._counter = $&value)
    other_provider: Provider = (._counter = $&other)
    counter ::= to_virtual#(CounterAccess)(&provider)
    other_counter ::= to_virtual#(CounterAccess)(&other_provider)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    set(.counter = other_counter)
    if other != 42 { abort }
    if unwrap_or_abort(.value = await($&future)) != 7 { abort }
    set(.counter = counter)
    if value != 42 { abort }
}
