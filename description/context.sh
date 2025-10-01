#!/bin/bash
# Crear el contenido a copiar
echo "----- ls -T -----"
ls -T

# Incluir todos los archivos
for f in ./*; do
    if [ -f "$f.md" ]; then
        echo ""
        echo "----- $f -----"
        cat "$f"
    fi
done

