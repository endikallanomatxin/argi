leaf := #import("../leaf")

read_leaf () -> (.status_code: Int32) := {
    status_code = leaf.leaf_value
}
