En todos los lenguajes, os.std_in, os.std_out, os.std_err son file descriptors globales que se inicializan al iniciar un progama, incluso aunque no importes stdio.h o similares.
Son variables globales de tipo *os.FILE que se pueden usar para leer y escribir.

Igual la forma de imprimir en nuestro lenguaje puede ser:

```
import os

os.std_out|write("Hello, world\n")

-- Para leer
line := os.std_in|read_line()
```

En go, en la librería os, están declaradas:

```go
var (
	Stdin  = NewFile(uintptr(syscall.Stdin), "/dev/stdin")
	Stdout = NewFile(uintptr(syscall.Stdout), "/dev/stdout")
	Stderr = NewFile(uintptr(syscall.Stderr), "/dev/stderr")
)
```

En zig, `File` es un struct que forma parte de la libreería `fs`.

En io se encuentran declaradas estas funciones:

```zig
pub fn getStdOut() File
```

```zig
pub fn getStdOut() File {
    return .{ .handle = getStdOutHandle() };
}
```

```zig
fn getStdOutHandle() posix.fd_t {
    if (is_windows) {
        return windows.peb().ProcessParameters.hStdOutput;
    }

    if (@hasDecl(root, "os") and @hasDecl(root.os, "io") and @hasDecl(root.os.io, "getStdOutHandle")) {
        return root.os.io.getStdOutHandle();
    }

    return posix.STDOUT_FILENO;
}
```

Viendo que depende del sistema operativo, igual lo mejor es que forme parte de `os`.
Aunque bueno, de alguna manera, zig hace eso también, pero abstrayendo lo mínimo.



Package layout:

- IO
	- Files
		- FILE
		- fopen, fclose, fread, fwrite, fseek, fprintf, fscanf
	- Std
		- Streams: stdin (teclado), stdout (consola), stderr
		- Write
			En C: printf (writes to stdout), puts, putchar
		- Read:
			En C: scanf (reads from stdint), fgets, getchar
		- Clear:
			En C: fflush

	- Terminal
		width, height, err := term.GetSize(int(os.Stdout.Fd()))

Un **stream** es una abstracción que representa una secuencia de datos que se pueden leer o escribir de forma continua. No importa si esos datos provienen de un archivo, del teclado, de la red o de cualquier otro dispositivo; el stream permite manipular esa entrada o salida de forma uniforme.

**Estructura FILE:**
En C, los streams se representan mediante punteros a estructuras de tipo `FILE`. Esta estructura interna contiene información como:

- **Puntero al buffer:** Área de memoria donde se almacenan datos temporalmente para optimizar las operaciones de lectura y escritura.
- **Modo de acceso:** Indica si el stream es de lectura, escritura o ambos.
- **Posición actual:** La posición en el buffer o en el archivo.
- **Estado y banderas:** Errores, fin de archivo, etc.


Por defecto, cada proceso tiene un único `stdin`, un único `stdout` y un único `stderr`, que son los streams estándar que hereda del sistema operativo (con descriptores 0, 1 y 2, respectivamente).

Aunque puedes tener múltiples streams en tu programa (otros archivos), el conjunto de streams estándar (`stdin`, `stdout` y `stderr`) es único para cada proceso.

```c
typedef struct _Stream {
    int fd;            // Descriptor de archivo, por ejemplo, 0 para stdin.
    char *buffer;      // Puntero a un buffer de memoria para operaciones de E/S.
    size_t buf_size;   // Tamaño del buffer.
    size_t pos;        // Posición actual dentro del buffer.
    int flags;         // Banderas de estado (error, EOF, modo lectura/escritura, etc.).
    // Podría incluir también punteros a funciones para leer/escribir, etc.
} Stream;
```

#### Serializing - Deserializing

>[!TIP] Good rust crate
> Serde - structs to json and other stuff

