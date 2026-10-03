main(.system: System) -> () := {
    child ::= unwrap_or_abort(.value = spawn(.self = system.proc_man, .executable = "test")).result
    duplicate := child
}
