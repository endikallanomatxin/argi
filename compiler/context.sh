#!/bin/bash
# Crear el contenido a copiar
echo "----- ls -T -----"
ls -T

# Incluir readme.md
if [ -f "README.md" ]; then
    echo ""
    echo "----- README.md -----"
    cat "README.md"
fi

# Incluir todos los archivos en src excepto .zig-cache
if [ -d "src" ]; then
    for f in src/*; do
        if [ "$(basename "$f")" = ".zig-cache" ]; then
            continue
        fi
        if [ -f "$f" ]; then
            echo ""
            echo "----- $f -----"
            cat "$f"
        fi
    done
fi

# Incluir test.rg
if [ -f "test.rg" ]; then
    echo ""
    echo "----- test.rg -----"
    cat "test.rg"
fi

# Incluir todos los archivos en test excepto .zig-cache
if [ -d "tests" ]; then
    for f in tests/*; do
        if [ "$(basename "$f")" = ".zig-cache" ]; then
            continue
        fi
        if [ -f "$f" ]; then
            echo ""
            echo "----- $f -----"
            cat "$f"
        fi
    done
fi

# Incluir build.zig y build.zig.zon
for file in build.zig build.zig.zon; do
    if [ -f "$file" ]; then
        echo ""
        echo "----- $file -----"
        cat "$file"
    fi
done
