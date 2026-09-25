dep := #import("../dep")

consume_imported(.value: dep.Abstract) -> (.result: Int32) := {
    result = 42
}
