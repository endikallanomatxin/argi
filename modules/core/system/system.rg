System : struct [
  terminal : $& Terminal,
  args     :  & Arguments,
  env_vars : $& EnvironmentVariables,
  file_sys : $& FileSystem,
  network  : $& Network,
  proc_man : $& ProcessManager,
  clock    : $& time.Clock,
  rand_gen : $& random.RandomNumberGenerator,
]

---
> - Otros sistemas y extensiones POSIX:
>   - getFileStatus :: FilePath -> IO FileStatus
>   - changeOwner :: FilePath -> UserID -> GroupID -> IO ()
>   - forkProcess :: IO () -> IO ProcessID
---
