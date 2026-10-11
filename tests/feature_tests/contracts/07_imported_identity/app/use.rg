dep := import ("../dep")

consume_imported(.value: dep.Capability) -> (.result: Int32) := {
    result = 42
}
