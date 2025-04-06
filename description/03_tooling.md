# Dev tools

## Build /Run System: Compiler / Interpreter

Usamos LLVM.

Hay que hacer que pueda:
- JIT (just in time)
	TODO: Explorar mejor como puede usarse para scripting.
- AOT (ahead of time)
Y que se puedan hacer algunas partes AOT y luego solo algunas partes JIT.

Si las carpetas son módulos, entonces igual se puede compilar módulo, de manera que se crea un ejecutable dentro de esa carpeta. Al importar, en lugar de correr los archivos del módulo, podría correr el ejecutable into el runtime.

Errores y warnings de compilación de rust o de gleam son muy buenos.

#### Build system

(like zig) el build de un programa se define en el mismo lenguaje:

Estaría bien que build.rg fuera un script que define como debe hacerse el build del programa. y que cuando hagas `rg build` se corra ese script y se buildee.

Por ejemplo un proyecto que resulta en un ejecutable.

```
src
	file.rg
	file.rg

build.rg
run.rg
test.rg
```


build.rg
```
target ::= standardTargetConfig
optimization ::= standardOptimizationConfig 

-- For example, using a library
llvm ::= Library[
	llvm_include_path ::= std.Build.LazyPath{ .cwd_relative = "/usr/.../llvm/includ" },
	llvm_lib_path     ::= std.Build.LazyPath{ .cwd_relative = "/usr/.../llvm/lib" },
]

-- To create an executable
exe ::= ExecutableConfig[
	name             ::= "argi_compiler"
	root_source_file ::= b.path("src/main.zig")
	target           ::= target
	optimize         ::= optimize
	libraries        ::= [llvm]
]
exe|build
```

run.rg
```
from build import exe

exe|build
exe|run(args)
```

test.rg
```
from build import target, optimize, llvm

tests ::= Tests[
	root_source_file = "..."
    target = target,
    optimize = optimize,
	libraries = [llvm]
]
tests|build
tests|run
```

O para una librería:

```
src
	file.rg
	file.rg

install.rg
test.rg
```

install.rg (o lo que quiera que se haga con una librería)
```
from build import target, optimize, llvm

lib ::= Library[
    name             = "argi_compiler",
    root_source_file = b.path("src/root.zig"),
	target           = target,
	optimize         = optimize,
	libraries        ::= [llvm]
]
lib|install
```


### Targets

Estaría bien que se pudiera compilar para microcontroladores, sistemas embedidos... Rust puede.
Que se pudiera compilar a JS o algo así para que permita hacer movidas de web?


### CLI args

Para correr con CLI args:
- `lang my_script.l arg1 arg2`
- `my_exec arg1 arg2`

CLI args are processed into a global constant `ARGS` (from julia)
