# Building

Usamos LLVM.

Copiar:

- cargo de rust, go, uv de python...
    Errores y warnings de compilación de rust o de gleam son muy buenos.

- zig build system

Los gestores de paquetes quieren la información de forma declarativa, pero la
forma procedural de zig es muy útil cuando hace falta más control. Lo mejor es
intentar encontrar un hibrido entre ambos.


## Specification file

- Es más limpio que sea declarativo (pyproject.toml)

- Es más versátil que sea procedural (build.zig)

Hay que encontrar un balance entre ambos.

project.rgstruct

```rg
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
    -- TODO: Pensar si separa los locks en otro archivo.
)

.commands = (

    -- Deben poder correr at compile time

    "build" = default_executable_creation (.module = "./entrypoints/main")
    -- o para librerías estáticamente linkadas.
    -- "build" = default_dynamically_linked_library_creation (.module = ".")

    "test"  = default_testing (.all_inside_folder = ".")

    "install" = (.ct: CommandContext) -> () {
        ct.do("build")
        -- Aquí procedural
    }

    "uninstall" = (.ct: CommandContext) -> () {
        -- Aquí procedural
    }

    "distribute" = (.ct: CommandContext) -> () {
        -- llena la carpeta dist/ con los compilados para todas las plataformas
    }

    "custom" = (.ct: CommandContext) -> () {
        -- Aquí procedural
    }
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

> [!IDEA] Gestión de dependencias externas.
> Lo mismo que conda puede asegurarse de que dispones de ciertas librerías, el
> sistema de build podría asegurarse de que tienes instalaciones concretas.
> Podría funcionar ruteando en función de la plataforma y probar a instalar con
> apt, brew, dnf...


## Targets

Estaría bien que se pudiera compilar para microcontroladores, sistemas embedidos... Rust puede.
Que se pudiera compilar a JS o algo así para que permita hacer movidas de web?

