# Building

> [!NOTE]
> This is an early proposal for a procedural build layer. Current packages use
> `argi.toml` and `[executables.*]` as described in `02_modules.md`.

We use LLVM.

Take inspiration from:

- Rust's Cargo, Go, Python's uv...
    Rust and Gleam have very good compile errors and warnings.

- Zig's build system

Package managers expect declarative information, while Zig's procedural
approach is useful when more control is needed. Find a balance between the two.


## Specification file

- Declarative configuration is cleaner (`pyproject.toml`).

- Procedural configuration is more versatile (`build.zig`).

Find a balance between the two.

Possible future `project.rgo`:

```rg
(
    .name                 = "Project Name"

    .version              = "1.0.0"

    .description          = "A brief description of the project."

    .readme               = "README.md"

    .minimum_argi_version = "0.1.0"

    .authors = (
        "Jhon Snow"
        "Arya Stark"
    )

    .license = ..MIT

    .dependencies = (
        "module_one" = (
            .path      = "http://example.com/module_one/"
            .version   = ">1.2.3"
            .lock_hash = "abcd1234efgh5678ijkl9012mnop3456qrst7890uvwx"
        )
        "module_two" = (
            .path      = "https://example.com/module_two/"
            .version   = ">2"
            .lock_hash = "wxyz1234abcd5678efgh9012ijkl3456mnop7890qrst"
        )
        -- TODO: Consider whether to put the lock data in another file.
    )

    .commands = (

        -- These commands must be able to run at compile time.

        "build" = default_executable_creation (.module = "source/app")
        -- Or for statically linked libraries.
        -- "build" = default_dynamically_linked_library_creation (.module = ".")

        "test"  = default_testing (.all_inside_folder = ".")

        "install" = (.ct: CommandContext) -> () {
            ct.do("build")
            -- Procedural code goes here.
        }

        "uninstall" = (.ct: CommandContext) -> () {
            -- Procedural code goes here.
        }

        "distribute" = (.ct: CommandContext) -> () {
            -- Fill dist/ with builds for all platforms.
        }

        "custom" = (.ct: CommandContext) -> () {
            -- Procedural code goes here.
        }
    )
)
```


building steps draft:

```
target := standardTargetConfig
optimization := standardOptimizationConfig 

-- For example, using a library
llvm : Library = (
	.llvm_include_path : std.Build.LazyPath = (.cwd_relative = "/usr/.../llvm/includ"),
	.llvm_lib_path : std.Build.LazyPath = (.cwd_relative = "/usr/.../llvm/lib" ),
)

-- To create an executable
exe : ExecutableConfig = (
	.name             = "argi_compiler"
	.root_source_file = b.path("src/main.zig")
	.target           = target
	.optimize         = optimize
	.libraries        = (llvm)
)

exe | build
```

running steps draft:

```
from build import exe

exe | build
exe | run (.executable = _, .args = ("arg1", "arg2"))
```

testing steps draft:

```
from build import target, optimize, llvm

tests : Tests = (
    .root_source_file = "..."
    .target = target,
    .optimize = optimize,
    .libraries = (llvm)
)
tests | build
tests | run
```

library steps draft:

```
from build import target, optimize, llvm

lib : Library = (
    name             = "argi_compiler",
    root_source_file = b.path("src/root.zig"),
    target           = target,
    optimize         = optimize,
    libraries        = (llvm)
)
lib | install
```

> [!IDEA] External dependency management.
> Like conda, the build system could ensure that certain libraries are available.
> It could select a package manager based on the platform and try installing
> dependencies with apt, brew, dnf, and similar tools.


## Targets

It would be useful to compile for microcontrollers and embedded systems, as Rust can.
Could we compile to JS or something similar to support web development?
