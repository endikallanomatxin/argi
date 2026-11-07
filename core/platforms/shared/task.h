#ifndef ARGI_TASK_H
#define ARGI_TASK_H
#include <stdint.h>

typedef void (*argi_task_buffer_start)(uintptr_t input, uintptr_t output);
/* Byte copies transport representations; they establish neither Argi reference
   validity nor ownership transfer.
   The worker owns input reads and output publication until join. The handle
   has one owner, whose join/destroy operations must be serialized.
   The callback must initialize the complete output before returning. Successful
   join establishes visibility before exposing that output to the owner. */
uintptr_t _argi_task_create_buffers(argi_task_buffer_start start, const void *input, uintptr_t input_size, uintptr_t output_size, uintptr_t input_alignment, uintptr_t output_alignment);
/* Result extraction succeeds once. Invalid sizes do not join or consume the
   result. A successful result address remains valid until task destruction. */
uintptr_t _argi_task_join_result(uintptr_t handle, uintptr_t size);
/* Copy initialized result bytes by value after successful result extraction.
   No pointer into native storage crosses this boundary. An invalid state/offset
   returns count zero; the unused suffix is always initialized to zero. */
struct argi_task_result_block { uint8_t bytes[32]; uintptr_t count; };
struct argi_task_result_block _argi_task_result_block(uintptr_t handle, uintptr_t offset);
/* Destroy joins if necessary; a join failure retains the handle and payload. */
int32_t _argi_task_destroy(uintptr_t handle);
#endif
