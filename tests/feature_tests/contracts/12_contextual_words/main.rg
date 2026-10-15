-- These spellings are contextual, so ordinary function names remain valid.
contract(.value: Int32) -> (.result: Int32) := { result = value + 1 }

satisfies(.value: Int32) -> (.result: Int32) := { result = value + 2 }

main() -> (.status_code: Int32 = 0) := {
    if contract(39).result + satisfies(0).result != 42 { abort }
}
