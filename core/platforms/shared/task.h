#ifndef ARGI_TASK_H
#define ARGI_TASK_H
#include <stdint.h>

typedef void (*argi_task_start)(uintptr_t handle);
typedef void (*argi_task_buffer_start)(uintptr_t input, uintptr_t output);
/* Payloads are copied bytes, not Argi references or ownership receipts.
   The worker owns input reads and output publication until join. The handle
   has one owner, whose await/destroy operations must be serialized. */
uintptr_t _argi_task_create(argi_task_start start, uintptr_t input, uintptr_t input_size, uintptr_t output_size);
uintptr_t _argi_task_create_buffers(argi_task_buffer_start start, const void *input, uintptr_t input_size, uintptr_t output_size, uintptr_t input_alignment, uintptr_t output_alignment);
int32_t _argi_task_read_input(uintptr_t handle, uintptr_t destination, uintptr_t size);
int32_t _argi_task_write_output(uintptr_t handle, uintptr_t source, uintptr_t size);
/* A successful result address remains valid until task destruction. */
uintptr_t _argi_task_join_result(uintptr_t handle, uintptr_t size);
int32_t _argi_task_await(uintptr_t handle, uintptr_t destination, uintptr_t size);
/* Destroy joins if necessary; a join failure retains the handle and payload. */
int32_t _argi_task_destroy(uintptr_t handle);
#endif
