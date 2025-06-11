EnvironmentVariables : Type = Map<String,String>

-- Si vienen pre-fetcheados, entonces es un map.
-- Si no vacío y syscalls en los get y set

-- get[] is the regular get of any map

op set$[]($&EnvironmentVariables, key: String, value: String) : !{
    -- Set is overloaded to modify the environment variables of the system
    -- via syscall
}

