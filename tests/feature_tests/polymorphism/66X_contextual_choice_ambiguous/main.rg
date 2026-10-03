First: Type = (..before, ..shared)
Second: Type = (..shared, ..after)
select(.tag: First) -> (.value: Int32) := { value = 1 }
select(.tag: Second) -> (.value: Int32) := { value = 2 }
main() -> (.status_code: Int32 = 0) := {
    value := select(.tag = ..shared)
}
