#ifndef ARGI_TASK_H
#define ARGI_TASK_H
#include <stdint.h>

/* Minted only for the callback invocation, after both buffers are acquired.
   Identity and addresses remain valid only until that callback returns. */
struct argi_execution_invocation {
    uintptr_t identity;
    uintptr_t input, output;
    uintptr_t input_size, output_size;
    uintptr_t input_alignment, output_alignment;
};
typedef void (*argi_task_buffer_start)(struct argi_execution_invocation invocation);
/* Byte copies transport representations; they establish neither Argi reference
   validity nor ownership transfer.
   The worker owns input reads and output publication until join. The handle
   has one owner, whose join/destroy operations must be serialized.
   The callback must initialize the complete output before returning. Successful
   join establishes visibility before exposing that output to the owner. */
uintptr_t _argi_task_create_buffers(argi_task_buffer_start start, const void *input, uintptr_t input_size, uintptr_t output_size, uintptr_t input_alignment, uintptr_t output_alignment);
/* Failure is possible only before invocation. Success has already executed
   the callback exactly once, with no worker or outstanding asynchronous use. */
uintptr_t _argi_task_create_inline_buffers(argi_task_buffer_start start, const void *input, uintptr_t input_size, uintptr_t output_size, uintptr_t input_alignment, uintptr_t output_alignment);
/* Certified reclaim performs synchronization itself; a flag supplied by the
   caller cannot stand in for successful joining. Failure retains the loan. */
int32_t _argi_execution_reclaim(uintptr_t handle);
/* A typed worker registers cleanup once after initializing its entire output.
   Only that invocation may register it. Successful join publishes both the
   bytes and cleanup. The serialized consumer can claim custody once using
   the matching cleanup operation. On success it must immediately move the
   owner out of the slot before releasing the task's backing storage. */
typedef void (*argi_task_result_cleanup)(uintptr_t storage);
int32_t _argi_task_own_result(uintptr_t identity, argi_task_result_cleanup cleanup);
uintptr_t _argi_task_take_owned_result(uintptr_t handle, argi_task_result_cleanup cleanup);
/* Joining publishes the result for repeatable inspection until destruction.
   Invalid sizes fail before join. The typed owner controls delivery. */
uintptr_t _argi_task_join_result(uintptr_t handle, uintptr_t size);
/* Copy initialized result bytes by value after successful join.
   No pointer into native storage crosses this boundary. An invalid state/offset
   returns count zero; the unused suffix is always initialized to zero. */
struct argi_task_result_block { uint8_t bytes[32]; uintptr_t count; };
struct argi_task_result_block _argi_task_result_block(uintptr_t handle, uintptr_t offset);
/* Destroy joins if necessary; a join failure retains the handle and payload. */
int32_t _argi_task_destroy(uintptr_t handle);
#endif
