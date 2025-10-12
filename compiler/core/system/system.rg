System : Type = (
  .terminal : $&Terminal
  .args     :  &Arguments
  .env_vars : $&EnvironmentVariables
  .file_sys : $&FileSystem
  .network  : $&Network
  .proc_man : $&ProcessManager
  .clock    : $&Clock
  .rand_gen : $&RandomNumberGenerator
  .ffi      : $&ForeignFunctionInterface
)

