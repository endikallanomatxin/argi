Box := <.T: Type> (
    .choice : (..present T, ..missing)
)

read := <.T: Type> (.box: &Box<T>) -> (.result: T) {
    match box&.choice {
        ..present value { result = value }
        ..missing { abort }
    }
}

computed ::= #run () -> (.result: Bool) {
    box ::= Box<Bool>(.choice = ..present true)
    result = read(&box).result
}

main() -> () := {
    box ::= Box<Bool>(.choice = ..present true)
    if read(&box).result {} else { abort }
    if computed {} else { abort }
}
