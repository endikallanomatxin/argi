FileSystem& : Type = []

FileOpeningMode : Type = [
    ..Read
    ..Write
]


open( &FileSystem&, path: String, mode: FileOpeningMode == ..Read)  : !FileHandle {
    ...
}


open($&FileSystem&, path: String, mode: FileOpeningMode == ..Write) : !FileHandle {
    ...
}


create($&FileSystem&, path: String) : ! {
    ...
}


remove($&FileSystem&, path: String) : ! {
    ...
}


rename($&FileSystem&, from: String, to: String) : ! {
    ...
}


get_working_directory($&FileSystem&, path: String) : ! {
    ...
}


set_working_directory($&FileSystem&, path: String) : ! {
    ...
}

list_directory($&FileSystem&, path: String) : ![String] {
    ...
}


