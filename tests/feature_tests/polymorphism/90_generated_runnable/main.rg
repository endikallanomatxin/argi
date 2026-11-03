double := (.x: Int32) -> (.result: Int32) { result = x * 2 }
nothing := () -> () {}
pair := (.x: Int32) -> (.first: Int32, .second: Int32) {
    first = x
    second = x + 1
}

Runnable#(.T: Type): Contract = (
    .run: (.self: $&T) -> () where {}
)

Task := #(.F: Function) (
    .args: inputs_of#(F),
    .output: ?result_of#(F) = ..none
)

implement#(.F: Function) Runnable#(Task#(F)) (
    .run = (.self: $&Task#(F)) -> () {
        value ::= invoke#(F)(.args = ~self&.args)
        self&.output = ..some(.value = ~value)
    }
)

main := () -> () {
    task ::= Task#(double)(.args = prepare_args#(double)(.args = (.x = 21)))
    runnable ::= to_virtual#(Runnable)($&task)
    run(.self = $&runnable)
    match task.output {
        ..some payload { if payload.value != 42 { abort } }
        ..none { abort }
    }
    empty_task ::= Task#(nothing)(.args = ())
    empty_runnable ::= to_virtual#(Runnable)($&empty_task)
    run(.self = $&empty_runnable)
    match empty_task.output {
        ..some _ {}
        ..none { abort }
    }
    pair_task ::= Task#(pair)(.args = (.x = 41))
    pair_runnable ::= to_virtual#(Runnable)($&pair_task)
    run(.self = $&pair_runnable)
    match pair_task.output {
        ..some payload {
            if payload.value.first != 41 or payload.value.second != 42 { abort }
        }
        ..none { abort }
    }
}
