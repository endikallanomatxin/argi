-- Minimal array abstraction; functionality will be expanded in the future.
Array#(.t: Type) : Type = (
    .data: $&t,
    .length: Int32 = 0,
)

-- init (.a: $&Array#(.t), .data: $&t, .length: Int32) -> () := {
--     a& = (.data = data, .length = length)
-- }
-- 
-- deinit (.a: $&Array#(.t)) -> () := {
--     -- Arrays view external storage for now; nothing to release.
-- }

-- operator get[](.self: &Array#(.t), .i: Int32) -> (.v: t) := {
--     arr :: Array#(.t) = self&
--     element_ptr : &t = arr.data + i
--     v = element_ptr&
-- }
-- 
-- operator set[](.self: $&Array#(.t), .i: Int32, .value: t) -> () := {
--     arr :: Array#(.t) = self&
--     element_ptr : $&t = arr.data + i
--     element_ptr& = value
-- }
