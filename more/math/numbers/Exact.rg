ExactRealNumber : Type = (
    -- For mathematicians.
    -- Stores the operations that produce an exact number.
    -- Allows viewing it in LaTeX.
    .operation_tree : OperationTree,
    ...
)

ExactRealNumber implements RealNumber

is_rational (.n: ExactRealNumber) -> (.r: Bool) := {
    -- Check if it is only describe by a ratio.
    ...
}
