once setup() -> () := {
}

helper() -> () := {
    setup()
}

test first(.system: System) -> !() := {
    helper()
}

test second(.system: System) -> !() := {
    helper()
}
