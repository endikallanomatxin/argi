# Learnings from Jai

A Programming Language for Games

## [Ideas about a new programming language for games](https://www.youtube.com/watch?v=TH9VCN6UkyQ&list=PLmV5I2fxaiCKfxMBrNsU1kgKJXD3PkyxO&index=1&t=193s)

### No big agenda

    - Everything functional
    - Full memory safety

Sound great, but are difficult to achieve.


### Why not other?

- GO
    - GC
    - Concurrency is too restrictive
- D (optional GC is a good idea)
    - Too much like C++
- Rust
    - Cares too much about safety
    - High friction


### Goals

- Friction reduction
- Joy of programming
- Performance
- Simplicity
- Designed for good programmers

Subgoals:
- Fast compilation
- Lack of tedium when expressing self in code
- Pleasant and helpful error messages

Wants it to stay productive even in large projects.

Prefers 85% solutions instead of "100% solutions".


### RAII (Resource Acquisition Is Initialization)

Doesn't like constructors and destructors.

> There is no such thing as a resource!

There are no resources, only memory.
We will only try to find a good solution for memory (85% solution).

> RAII exists because of exceptions


### Exceptions

Exceptions are silly

Exceptions inject a lot of complexity into the language.

Go does errors right.


### Pointers

We are not afraid of pointers.


### REAL GOAL: Helping with memory

C++ let's me initialize structs nicely.

He shows an idea:

    ```
    struct Party_Member {
        char *! character_name = NULL;
        char *! class_name = NULL;

        int healt_max = 4;
        int member_flags = 0;
        int experience = 0;

        int current_level = 1;
    }
    ```
    Notice the `!`. It documents memory ownership.

### Arrays

Arrays should be range checked in debug.

Ejemplo de array respecto de C:

```c
struct Mesh {
    Vector3 positions[];
    int indices[];
}
```

El propone:

```
struct Mesh {
    vector3 [] positions;
    int [] indices;
}
```

If they are arrays that you own:

```
struct Mesh {
    vector3 []! positions;
    int []! indices;
}
```

### Heap allocation is expensive

Going around this makes code very complix in c++
It should be easier to tell the compiler to allocate things together.

```
struct Mesh {
    vector3 []! positions;
    int []! indices; @joint positions
}
```

It's an easy compiler optimization.

In C this kind of code is scary, but we can make it not scary.

We have to make this kind of memory otimization easy, and a small syntactic
step from the non-optimized code.


### No header files

### Refactorability

In c++ it is terrible. Go does it right.

Lambda syntax should be the same as function syntax.

He likes optional types.


### Concurrency!!!

Explicit data capture would be really helpful.

### Fewer / No Implicit Type Conversions


### named argument passing

They are helpful.

Maybe even make it mandatory for args with default values.

Maybe shouldn't go that far as making every one named, but its good.

### Introspection and serialization

Should be easy.

### Building

The program should specify how to build the program.

### Permissive license

Free, gpl...

### Creature comforts

- (good numbers by default?)
- Nested block comments.
- A better or no preprocessor. Compiletime function execution.
- Language support for hot reloading code.

- Doesn't like scripting
- Doesn't like inheritance and oop.



## [Declarations and factorability](https://www.youtube.com/watch?v=5Nc68IdNKdg&list=PLmV5I2fxaiCKfxMBrNsU1kgKJXD3PkyxO&index=2)


### Best practices

"Best practices" are usually not good.

Usually new languages tend to enforce them.


### Breaking functions

This is usually recommended:

```c
void MinorFunction1() {
    ...
}

void MinorFunction2() {
    ...
}

void MajorFunction() {
    MinorFunction1();
    MinorFunction2();
}
```

The program as a wholes gets harder to understand.

It was linear easy to understand. Now the minor functions look like the are a
more complex and general thing that can be called outside.

Non-pure functions can make stuff complex.

> Jhon Carmack:
> If a lot of operations are supposed to happen in a sequential fashion, their code should follow sequentially.

Sometimes we can use locally-scoped functions. They increase hygiene.

Best to postpone breaking code into functions.

Rust lambda vs top-level are too different.


### Assignment Syntax

Sean's declaration syntax:

```
f: float;     // Declare f, explicit type.
f: float = 1; // Declare and initialize.
f:= 1;        // Declare f, implicit type.
f = 1;        // Assign f, must be declared.
```

For functions, desires:

- Paste function between local and global scope.
- Switch between named and unnamed.
- Switch between method and not.

Proposes:

```
square := (x: float) -> float { return x * x; }
```

Capture syntax:

```
f := (x: flaot) -> float [y] { return x * y; }
```

We don't want the capture to be considered part of the type. So let's keep the type clean on the left.

Yo can apply the capture to any block.

It is useful to start the layout for dividing your code into functions.

```
a_lot_of_code();
happens = up + here;

// Set up the people.
Array<Character *> people;

[&people] {
    auto character = new Character();
    character->name = copy_string("Larry");
    people.add(character);
}();

much_more();
code = happens;
down += here;
```

blocks cannot access outside variables.

This also makes it easier to make it thread-safe.

Also for globals:

```
auto pathfind = (Grid *grid, int start, int end) -> Path_Result
    [globals.path_debug_config] {
    
    // Because of the capture, our lexical scope is
    // narrowed to only path_debug_config.
    
    ...
};
```

They make impure functions more like pure functions.

Banning globals is not a good idea.
You should decide when to ditch them.


### Notes

(He likes data-oriented programming (Mike Acton).)

> Comments are code that never runs, probably buggy.

Doesn't like const being part of the type.


## [Compile time code execution demo](https://www.youtube.com/watch?v=UTqZNujQOlA&list=PLmV5I2fxaiCKfxMBrNsU1kgKJXD3PkyxO&index=3)

### Comptime

He thinks it is a key feature. A priority.

Everything that can be run in the language can be run at compile time.

It uses bytecode.

- `#run` to run in compile time.
- `#check_call function_name check_function_name` to run something after every
function call. To check input mainly.

### Building

```
#import "Basic";
#import "GL";

DIR :: "/jai/traveller";

main :: () {
    setcwd(DIR);
    invaders();
}

build :: () {
    // Print initial state:

    s := #filepath;
    printf("file path is: %s\n", s);

    printf("build_options.executable_name = %s\n", build_options.executable_name);
    printf("build_options.output_path = %s\n", build_options.output_path);

    /* Set options we would like:
    build_options.optimization_level = Optimization_Level.DEBUG;
    build_options.emit_line_directives = false;
    build_options.executable_name = "traveller";
    */
    update_build_options();

    // Load files:
    set_build_file_path(#filepath);
    add_build_file("misc.jai");
    add_build_file("invaders.jai");
    add_build_file("checks.jai");
    add_build_file("levels.jai");
}

#run build();

build_common :: () {
    s := #filepath;
    // …
}
```

### Notes

- Function overloading le gusta


## [Iteration and arrays, uninitialized values, enums](https://www.youtube.com/watch?v=-UPFH0eWHEI&list=PLmV5I2fxaiCKfxMBrNsU1kgKJXD3PkyxO&index=4)

for y while son una discontinuidad en como se escribe codigo. funcion parecida sintaxis distinta. Hay que buscar syntax uniforme.

```
// 4. Array types

// why put work into building arrays into the language?
// See "C's Biggest Mistake", Water Bright, December 2009.
// http://www.drobbits.com/articles/architecture-and-design/cs-biggest-mistake/228701625
// Note: The syntax here is different than the C syntax proposed in Bright's article.

print_int_array :: (array: [] int) {    // This [] int consists of a pointer and a length.
    printf("Array has %d items:\n", array.count);

    for i : 0..array.count-1 {
        printf("    array[%d] = %d\n", i, array[i]);
    }
}

part4 :: () {
    static_array: [N] int;              // In C: int static_array[N];
    dynamic_array: [...] int;           // No built-in C equivalent.

    // Set up the arrays.

    for 0..N-1 {
        static_array[it] = it;
        // Slightly weird syntax for adding to dynamic arrays, will be
        // improved when we have parameterized types.
        array_add(&dynamic_array, ^it);
    }

    // We can pass either static_array or dynamic_array to print_int_array.
    // They will both implicitly cast to [].

    print_int_array(static_array);
    print_int_array(dynamic_array);
}

/*
Note: In the future you will be able to set index sizes, in some way like:
    [N : u16] float;
    [.. : u32] float;
*/
```

El indicador de que es un vector [] tiene que ir antes del tipo.

Hay `[N]` para arrays de tamaño fijo,`[]` para arrays de tamaño desconocido (input de función, por ejemplo) y `[...]` para arrays de tamaño dinámico.



## [Data-Oriented Demo: SOA, composition](https://www.youtube.com/watch?v=ZHqFrNyLlpA&list=PLmV5I2fxaiCKfxMBrNsU1kgKJXD3PkyxO&index=6)

### Data-oriented programming

What does "data-oriented" mean?

In order of approachability:

Noel Llopis, "Data-Oriented Design"
http://gamesfromwithin.com/data-oriented-design

Chandler Carruth, "Efficiency with Algorithms, Performance with Data Structures"
https://www.youtube.com/watch?v=fHNnRkzxHWs

Mike Acton, "Data-Oriented Design in C++"
https://www.youtube.com/watch?v=rX0ItVEVjHC

It means the language is helping you set up things the way you want in memory,
without loss of efficiency,
without loss of high-level expressiveness.

Can we provide a smooth pathway where you can build something simple,
but incrementally augment it as needed to get speed?


### More comfortable encapsulation

`using` keyword to make easier to use encapsulation.

```c
print_position_test :: () {
    Entity :: struct {
        position: Vector3;
    }

    print_position_a :: (entity : ^Entity) {
        printf("print_position_a: (%f, %f, %f)\n",
               entity.position.x, entity.position.y, entity.position.z);
    }

    print_position_b :: (entity : ^Entity) {
        using entity;
        printf("print_position_b: (%f, %f, %f)\n",
               position.x, position.y, position.z);
    }

    print_position_c :: (using entity : ^Entity) {
        printf("print_position_c: (%f, %f, %f)\n",
               position.x, position.y, position.z);
    }

    print_position_d :: (entity : ^Entity) {
        using entity.position;
        printf("print_position_d: (%f, %f, %f)\n", x, y, z);
    }

    e : Entity;

    print_position_a(^e);
    print_position_b(^e);
    print_position_c(^e);
}
```

Also can be used inside structs:

```c
// Like the previous example,
// but designate the entity with 'using',
// so we no longer need to explicitly access that sub-field:

door_test_2 :: () {
    Entity :: struct {
        position: Vector3;
    }
    Door :: struct {
        using entity : Entity;      // 'entity' is both named *and* anonymous.
        openness_current : float = 0;
        openness_target  : float = 0;
    }

    door : Door;
    printf("door_test_2: door.position is (%f, %f, %f)\n",
           door.position.x, door.position.y, door.position.z);

    // We can also implicitly cast from Door to Entity, like you would
    // get with C++ subclassing:
    print_position :: (using entity : Entity) {
        printf("door_test_2b: position is (%f, %f, %f)\n",
               position.x, position.y, position.z);
    }

    print_position(door.entity);
    print_position(door);

    // This kind of 'using' is like an anonymous struct in C,
    // but it can also be non-anonymous, because it is named!
    // (For example, when passing door.entity above).
}
```

It allows for easier encasulation.

Even spliting encapsulated data in several without having to modify code.

```c
Entity_Hot :: struct {
    position     : Vector3;
    orientation  : Quaternion;
    scale        : float = 1;
    flags        : u32;
};

Entity_Cold :: struct {
    label            : ^u8;
    group            : ^Group;

    mount_parent_id  : int;
    mount_position   : Vector3;
    mount_orientation: Quaternion;
    mount_scale      : float;
    mount_bone_index : int;
    ...
};

Entity :: struct {
    using hot  : ^Entity_Hot;
    using cold : ^Entity_Cold;
};

Door :: struct {
    using entity : Entity;    // By value, so we don't jump through an extra pointer here.
    float openness_current;
};

// Now we can change our mind during development about what is 'hot'
// and what is 'cold', without having to rewrite the code that uses those members.
```


### Structures of Arrays (SOA)

> For some arrays, we can get much better cache performance
> by changing the order of data. C++ encourages the use
> of arrays of structures (AOS), but most CPUs are happier
> when data is laid out as structures of arrays (SOA).
>
> It therefore seems reasonable that a data-oriented language
> would make it easy to put your data in SOA.


Se pone tras declarar el vector:

```
a : [N] Vector3;
b : [N] SOA Vector3;
```

Se comporta igual que si fuera un AOS.

También se aplica a punteros

```c
Door :: struct {
    using entity: ^ SOA Entity;
    openness_current: float;
    openness_target: float;
};
```

No entiendo muy bien como funciona eso.

Making a struct SOA by default:

```c
Entity :: struct SOA {
    ...
};
```

Eso hace que siempre que se cree una lista de eso se comporte como SOA, y así evitas ponerlo cada vez.
Con una sola palabra, haces todo más eficiente.

Luego se puede usar `AOS` para sobreescribirlo en un caso concreto.

```c
my_array : [N] AOS Entity;
```

AOS and SOA pointers can be automatically casted.






