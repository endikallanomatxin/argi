-- Only the bundled-core declaration is trusted. This similarly named user
-- function must not discharge opaque dependencies.
trusted_opaque_mark_empty(.storage: $&Allocation) -> () := {
}
