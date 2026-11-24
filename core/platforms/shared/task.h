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
typedef void (*argi_task_result_cleanup)(uintptr_t storage);
/* Return NULL for plain output or its typed destructor for owned output. */
typedef argi_task_result_cleanup (*argi_task_buffer_start)(struct argi_execution_invocation invocation);
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
/* Caller custody may outlive a submitted receipt. The typed caller keeps the
   slot alive through submission and task release. Operations on the slot and
   task handle are serialized by that owner. A failed start leaves it empty.
   A successful release publishes the buffer without running user cleanup. */
uintptr_t _argi_task_output_create(argi_task_buffer_start entry);
/* Acceptance survives join, receipt release, and output extraction. Only
   the slot owner may query it after the submit call returns. */
int32_t _argi_task_output_accepted(uintptr_t slot, argi_task_buffer_start entry);
/* Transfer output custody from the acceptance slot back to its live task.
   The slot remains an acceptance proof and can be destroyed afterwards. */
int32_t _argi_task_output_detach(uintptr_t slot, uintptr_t task, argi_task_buffer_start entry);
/* A zero slot selects output owned by the task receipt. */
uintptr_t _argi_task_start_buffers(uintptr_t slot, int32_t inline_run,
    argi_task_buffer_start entry, const void *input, uintptr_t input_size,
    uintptr_t output_size, uintptr_t input_alignment, uintptr_t output_alignment);
/* A successful take transfers custody of the initialized value. The typed
   consumer must move or drop it before destroying the slot and its buffer. */
uintptr_t _argi_task_output_take(uintptr_t slot, argi_task_buffer_start entry);
int32_t _argi_task_output_destroy(uintptr_t slot);
/* Certified reclaim performs synchronization itself; a flag supplied by the
   caller cannot stand in for successful joining. Failure retains the loan. */
int32_t _argi_execution_reclaim(uintptr_t handle);
/* Successful join publishes the initialized output and its worker-returned
   destructor. A matching consumer can claim the owner once, then must move
   it out before releasing the backing storage. */
uintptr_t _argi_task_take_owned_result(uintptr_t handle, argi_task_result_cleanup cleanup);
/* Joining publishes the result for repeatable inspection until destruction.
   Invalid sizes fail before join. The typed owner controls delivery. */
uintptr_t _argi_task_join_result(uintptr_t handle, uintptr_t size);
/* Copy initialized result bytes by value after successful join.
   No pointer into native storage crosses this boundary. An invalid state/offset
   returns count zero; the unused suffix is always initialized to zero. */
struct argi_task_result_block { uint8_t bytes[32]; uintptr_t count; };
struct argi_task_result_block _argi_task_result_block(uintptr_t handle, uintptr_t offset);
/* Release can free plain or already claimed storage. A pending owner leaves
   the handle intact. This entry never invokes a result destructor. */
int32_t _argi_task_release_storage(uintptr_t handle);
/* Destroy joins if necessary; a join failure retains the handle and payload. */
int32_t _argi_task_destroy(uintptr_t handle);
#endif
