ProcessManager : Type = ()

once init(.p: $&ProcessManager) -> () := {
}

-- The capability for calling processes


-- ProcessHandle : Type = [
--    .id: Int64
-- ]
-- 
-- 
-- call(pc: $&ProcessCaller&, command: String) : !ProcessHandle {
--     ...
-- }
-- 
-- 
-- read(ph: $&ProcessHandle&) : !String {
--     -- Igual debería tener streams el handle para esto.
--     ...
-- }
-- 
-- 
-- terminate(ph: $&ProcessHandle&) : ! {
--     ...
-- }
-- 
-- 
-- deinit(ph: $&ProcessHadle&) : {
--     ph|terminate($&_)
-- }
-- 
--    - forkProcess :: IO () -> IO ProcessID
