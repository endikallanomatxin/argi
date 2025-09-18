# Multiple Dispatch

Functions are dispatched based on:

- the name of the function,

- the types of the input-fields

Note that:

- Input field names are not considered for dispatching (as it is possible to
omit them when calling functions).

- Compile-time-parameters are not considered for dispatching.

- return types are used to infer the resulting types, but not used for
dispatching.

- Specific value checks cannot be used for dispatching.

Thus, you cannot redefine a function with the same name and input fields, but
with different input-field names compile-time-parameters or return types.

