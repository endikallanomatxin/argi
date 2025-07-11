# Modules and imports

Folders as modules, como Go y odin. El nombre del módulo es el nombre de la
carpeta.

Every file in a directory can see each other, same namespace.

## Project layout

There is a layout convention:

```
-- Simple layout for libraries
library_project/
├── README.md
├── module.rgstruct
├── submodule/
│   ├── file1.rg
│   ├── file2.rg
│   └── file3.rg
└── submodule2/
    ├── file1.rg
    ├── file2.rg
    └── file3.rg

-- Complex layout for applications
project_to_compile/
├── README.md
├── project.rgstruct
├── src/
│   ├── module_that_becomes_executable/
│   │   ├── file1.rg
│   │   ├── file2.rg
│   │   └── file3.rg
│   └── module_that_gets_imported/
│       ├── file1.rg
│       ├── file2.rg
│       └── file3.rg
│    -- Los módulos se comportan como si estuvieran directamente en la raíz.
│    -- igual hacer que dentro de src/ haya un entrypoints/, internal/ y external/?
│    -- O igual con usar la _ para la privacidad ya es suficiente?
│    -- O mejor todo plano fuera?
│
└── bin/
    └── module_that_becomes_executable

```

> [!TODO] Pensar en una forma de poner dependencias, que igual estaría bien definir la versión en un sitio común y luego los archivos en ese módulo que puedan acceder a ese módulo.

> [!IDEA] Separar módulos entre:
> - entrypoints/
> - internal_modules/
> - external_modules/
> Se puede hacer que si hay ese layout entonces solo exporta external_modules


## Building

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
    "build" = default_executable_creation (.module = "./entrypoints/main")
    -- o para librerías:
    "build" = default_library_creation (.module = "./external/some_library")

    "test"  = default_testing (.all_inside_folder = ".")

    "install" = (.ct: CommandContext) -> () {
        ct.do("build")
        -- Aquí procedural
    }

    "uninstall" = (.ct: CommandContext) -> () {
        -- Aquí procedural
    }

    "custom" = (.ct: CommandContext) -> () {
        -- Aquí procedural
    }
)
```


Si no también puede hacerse que sea una función:

```rg
project () -> (.config: ProjectConfig) := {
    config = (
	...
    )
}
```

Igual obligar a que tenga una valor at compile time.


> [!IDEA] Declaración de cuerpos de funciones en otros archivos
> 
> ```rg
> project () -> (.config: ProjectConfig) := {
>     #file("./project_config.rg")
> }
> ```
> Así se podría usar un archivo así para la config o build o lo que sea.


Igual rgs es el camino si hiciéramos eso.


## Importing

To import from other modules:

- `m := #import("./module/")`

- `some_function := #import("./module/").some_function`

- `(one, two) := #import("./module/").(one, two)`

    o

    `one = m.one`
    `two = m.two`

(que sea una sintaxis acorde al código normal permite programar imports en
compile time)


## Locating modules

If it is just a name, then it can be:
- a locally defined module alias.
- a global module installed in the system.

If the module starts with a . then it is relative to the current module. (inside)
If it starts with .. then it is relative to the parent module. (outside)

/ are used to refer to modules inside other modules.

> [!IDEA] Que import reciba un enum con el tipo de import que es.
> Por ejemplo:
>  ```rg
>  m := #import("./module/", ..Relative)
>  m := #import("module", ..Global)
>  m := #import("module", ..Local)
>  ```


## Protected modules

Modules which name starts with _ are not visible outside the module. They are
private to the module.


## Interpretation and imports

Lua tiene:
- require corre si no ha corrido ya (cache)
- dofile corre sin considerar el cache
- loadfile importa sin correr. Se puede correr a posteriori

Python por defecto corre todo lo importado linea a linea, y hay que hacer `if __name__ == "__main__":` para que no corra si se importa.

Tiene sentido que se pueda importar "scripts"?

Podríamos hacer:
- `run_if_not_yet(module)`
- `run(module)`
- `import(module)`


Igual es buena idea también separar los archivos que se pueden correr, de los
que se pueden importar:

- Files inside a module: `script.rg`
- Scripts: `script.rgs`

