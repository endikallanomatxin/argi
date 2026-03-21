ExactRealNumber : Type = (
    -- Para matemáticos
    -- Guarda las operaciones que llevan a un número exacto
    -- Permite verlo en LaTeX. 
    .operation_tree : OperationTree,
    ...
)

ExactRealNumber implements RealNumber

is_rational (.n: ExactRealNumber) -> (.r: Bool) := {
    -- Check if it is only describe by a ratio.
    ...
}

