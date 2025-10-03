Codecs is a name for englobing a set of modules that are used to encode and decode data:

- `archive` Formats for compressing folders.
- `compression` Formats for compressing files.
- `encoding`
- `serialization`


Linkea con zlib
- Qué ofrece: compresión / descompresión DEFLATE (gzip, PNG, ZIP).
- Por qué importa: es el estándar para pares de datos comprimidos en red, formatos de archivo y sistemas embebidos. Casi cualquier proyecto que haga I/O pesado lo enlaza dinámicamente para obtener máxima velocidad sin reinventar el algoritmo.

linkea con FFmpeg (libavcodec / libavformat / libavutil)
- Qué ofrecen: códecs de audio/vídeo (H.264, VP9, AAC…), wrappers de contenedores (MP4, MKV) y utilidades varias.
- Por qué importa: servidores de streaming, editores de vídeo, reproductores multimedia y hasta videojuegos utilizan FFmpeg para transcodificar, extraer frames o mezclar pistas sin escribir un solo bit de ensamblador de códecs.

