; ModuleID = 'argi_module'
source_filename = "argi_module"

@__argi_runtime_argc_global = global i64 0
@__argi_runtime_argv_global = global i64 0
@__argi_vtable_0 = constant { ptr } { ptr @"deallocate__f47__in_s{self:prw_s{},data:prw_u8,size:unative}__out_s{}" }
@__argi_vtable_1 = constant { ptr } { ptr @"deallocate__f57__in_s{self:prw_s{backing_allocator:prw_s{},blocks:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},domain:s{marker:bool},block_size:unative,current_block_offset:unative},data:prw_u8,size:unative}__out_s{}" }
@__argi_vtable_2 = constant { ptr } { ptr @"deallocate__f61__in_s{self:prw_s{page_size:unative},data:prw_u8,size:unative}__out_s{}" }
@argi.strlit.0 = private constant [3 x i8] c"rb\00"
@argi.strlit.1 = private constant [3 x i8] c"wb\00"
@argi.strlit.2 = private constant [3 x i8] c"ab\00"
@trace_source_file = private unnamed_addr constant [68 x i8] c"/home/endika/Projects/argi/zig-out/lib/argi/core/testing/testing.rg\00", align 1
@trace_source_line = private unnamed_addr constant [32 x i8] c"    test_fail_impl() !! message\00", align 1
@trace_source_file.1 = private unnamed_addr constant [68 x i8] c"/home/endika/Projects/argi/zig-out/lib/argi/core/testing/testing.rg\00", align 1
@trace_source_line.2 = private unnamed_addr constant [32 x i8] c"    test_fail_impl() !! message\00", align 1
@trace_source_file.3 = private unnamed_addr constant [68 x i8] c"/home/endika/Projects/argi/zig-out/lib/argi/core/testing/testing.rg\00", align 1
@trace_source_line.4 = private unnamed_addr constant [32 x i8] c"    test_skip_impl() !! message\00", align 1
@trace_source_file.5 = private unnamed_addr constant [68 x i8] c"/home/endika/Projects/argi/zig-out/lib/argi/core/testing/testing.rg\00", align 1
@trace_source_line.6 = private unnamed_addr constant [32 x i8] c"    test_skip_impl() !! message\00", align 1
@"argi.strlit.3\AA\AA\AA\AA\AA\AA\AA\AA\AA" = private constant [35 x i8] c"expect failed: condition was false\00"
@trace_source_file.7 = private unnamed_addr constant [68 x i8] c"/home/endika/Projects/argi/zig-out/lib/argi/core/testing/testing.rg\00", align 1
@trace_source_line.8 = private unnamed_addr constant [59 x i8] c"    fail(.message = \22expect failed: condition was false\22)!\00", align 1
@"argi.strlit.4\AA\AA\AA\AA\AA\AA\AA\AA\AA" = private constant [35 x i8] c"expect failed: condition was false\00"
@trace_source_file.9 = private unnamed_addr constant [68 x i8] c"/home/endika/Projects/argi/zig-out/lib/argi/core/testing/testing.rg\00", align 1
@trace_source_line.10 = private unnamed_addr constant [59 x i8] c"    fail(.message = \22expect failed: condition was false\22)!\00", align 1
@"argi.strlit.5\AA\AA\AA\AA\AA\AA\AA\AA\AA" = private constant [35 x i8] c"expect failed: condition was false\00"
@trace_source_file.11 = private unnamed_addr constant [68 x i8] c"/home/endika/Projects/argi/zig-out/lib/argi/core/testing/testing.rg\00", align 1
@trace_source_line.12 = private unnamed_addr constant [59 x i8] c"    fail(.message = \22expect failed: condition was false\22)!\00", align 1
@__argi_vtable_3 = constant { ptr } { ptr @"deallocate__f159__in_s{self:prw_s{allocation_attempts:i32,deallocations:i32,backing_freed_after_elements:bool},data:prw_u8,size:unative}__out_s{}" }
@trace_source_file.13 = private unnamed_addr constant [71 x i8] c"/home/endika/Projects/argi/zig-out/lib/argi/core/lists/DynamicArray.rg\00", align 1
@trace_source_line.14 = private unnamed_addr constant [39 x i8] c"        element ::= copy(.self = ptr)!\00", align 1
@trace_source_file.15 = private unnamed_addr constant [71 x i8] c"/home/endika/Projects/argi/zig-out/lib/argi/core/lists/DynamicArray.rg\00", align 1
@trace_source_line.16 = private unnamed_addr constant [39 x i8] c"        element ::= copy(.self = ptr)!\00", align 1

declare void @putchar(i8)

declare i32 @getchar()

declare void @puts(ptr)

declare i64 @strlen(ptr)

declare ptr @getenv(ptr)

declare ptr @fdopen(i32, ptr)

declare ptr @fopen(ptr, ptr)

declare i32 @fclose(ptr)

declare i32 @fflush(ptr)

declare i64 @fread(ptr, i64, i64, ptr)

declare i64 @fwrite(ptr, i64, i64, ptr)

declare i32 @feof(ptr)

declare i32 @ferror(ptr)

declare i32 @remove(ptr)

declare i32 @rename(ptr, ptr)

declare i32 @access(ptr, i32)

declare ptr @alloca(i64)

declare ptr @malloc(i64)

declare ptr @aligned_alloc(i64, i64)

declare i64 @getpagesize()

declare void @free(ptr)

declare void @memcpy(ptr, ptr, i64)

define i64 @argi_runtime_argc() {
entry:
  %runtime.argc = load i64, ptr @__argi_runtime_argc_global, align 4
  ret i64 %runtime.argc
}

define i64 @argi_runtime_argv() {
entry:
  %runtime.argv = load i64, ptr @__argi_runtime_argv_global, align 4
  ret i64 %runtime.argv
}

define {} @"init__f35__in_s{p:prw_s{}}__out_s{}"({ ptr } %0) {
entry:
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %p, align 8
  ret {} undef
}

declare { i64 } @"fread_into__f36__in_s{buffer:s{data:prw_u8,length:unative},stream:pro_any}__out_s{count:unative}"({ { ptr, i64 }, ptr })

declare { i64 } @"fwrite_from__f37__in_s{buffer:s{data:prw_u8,length:unative},stream:pro_any}__out_s{count:unative}"({ { ptr, i64 }, ptr })

declare {} @"memcpy_bytes__f38__in_s{dst:s{data:prw_u8,length:unative},src:s{data:prw_u8,length:unative}}__out_s{}"({ { ptr, i64 }, { ptr, i64 } })

define { ptr } @"mutable_reinterpret_reference__f161__in_s{base:prw_u8}__out_s{reference:prw_any}"({ ptr } %0) {
entry:
  %reference = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %base = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %base, align 8
  store i1 false, ptr %needs.deinit1, align 1
  %base2 = load ptr, ptr %base, align 8
  %ptr.to.int = ptrtoint ptr %base2 to i64
  %base3 = load ptr, ptr %base, align 8
  %ptr.to.int4 = ptrtoint ptr %base3 to i64
  %int.to.ptr = inttoptr i64 %ptr.to.int4 to ptr
  %base5 = load ptr, ptr %base, align 8
  %ptr.to.int6 = ptrtoint ptr %base5 to i64
  %int.to.ptr7 = inttoptr i64 %ptr.to.int6 to ptr
  store ptr %int.to.ptr7, ptr %reference, align 8
  store i1 true, ptr %needs.deinit1, align 1
  %1 = load ptr, ptr %reference, align 8
  %2 = insertvalue { ptr } undef, ptr %1, 0
  ret { ptr } %2
}

declare { ptr } @"reinterpret_reference__f162__in_s{base:prw_u8}__out_s{reference:pro_any}"({ ptr })

define {} @"memcpy_bytes__f39__in_s{dst:s{data:prw_u8,length:unative},src:s{data:pro_u8,length:unative}}__out_s{}"({ { ptr, i64 }, { ptr, i64 } } %0) {
entry:
  %src = alloca { ptr, i64 }, align 8
  %needs.deinit3 = alloca i1, align 1
  %needs.deinit4 = alloca i1, align 1
  %needs.deinit5 = alloca i1, align 1
  %dst = alloca { ptr, i64 }, align 8
  %needs.deinit = alloca i1, align 1
  %needs.deinit1 = alloca i1, align 1
  %needs.deinit2 = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  store i1 false, ptr %needs.deinit2, align 1
  store i1 false, ptr %needs.deinit3, align 1
  store i1 false, ptr %needs.deinit4, align 1
  store i1 false, ptr %needs.deinit5, align 1
  %arg = extractvalue { { ptr, i64 }, { ptr, i64 } } %0, 0
  store { ptr, i64 } %arg, ptr %dst, align 8
  %arg6 = extractvalue { { ptr, i64 }, { ptr, i64 } } %0, 1
  store { ptr, i64 } %arg6, ptr %src, align 8
  %dst7 = load { ptr, i64 }, ptr %dst, align 8
  %fld = extractvalue { ptr, i64 } %dst7, 0
  %lit.insert = insertvalue { ptr } undef, ptr %fld, 0
  %call = call { ptr } @"mutable_reinterpret_reference__f161__in_s{base:prw_u8}__out_s{reference:prw_any}"({ ptr } %lit.insert)
  %call.unpack = extractvalue { ptr } %call, 0
  %src8 = load { ptr, i64 }, ptr %src, align 8
  %fld9 = extractvalue { ptr, i64 } %src8, 0
  %lit.insert10 = insertvalue { ptr } undef, ptr %fld9, 0
  %call11 = call { ptr } @"reinterpret_reference__f163__in_s{base:pro_u8}__out_s{reference:pro_any}"({ ptr } %lit.insert10)
  %call.unpack12 = extractvalue { ptr } %call11, 0
  %dst13 = load { ptr, i64 }, ptr %dst, align 8
  %fld14 = extractvalue { ptr, i64 } %dst13, 1
  %lit.insert15 = insertvalue { ptr, ptr, i64 } undef, ptr %call.unpack, 0
  %lit.insert16 = insertvalue { ptr, ptr, i64 } %lit.insert15, ptr %call.unpack12, 1
  %lit.insert17 = insertvalue { ptr, ptr, i64 } %lit.insert16, i64 %fld14, 2
  %1 = extractvalue { ptr, ptr, i64 } %lit.insert17, 0
  %2 = extractvalue { ptr, ptr, i64 } %lit.insert17, 1
  %3 = extractvalue { ptr, ptr, i64 } %lit.insert17, 2
  call void @memcpy(ptr %1, ptr %2, i64 %3)
  ret {} undef
}

define { ptr } @"reinterpret_reference__f163__in_s{base:pro_u8}__out_s{reference:pro_any}"({ ptr } %0) {
entry:
  %reference = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %base = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %base, align 8
  store i1 false, ptr %needs.deinit1, align 1
  %base2 = load ptr, ptr %base, align 8
  %ptr.to.int = ptrtoint ptr %base2 to i64
  %base3 = load ptr, ptr %base, align 8
  %ptr.to.int4 = ptrtoint ptr %base3 to i64
  %int.to.ptr = inttoptr i64 %ptr.to.int4 to ptr
  %base5 = load ptr, ptr %base, align 8
  %ptr.to.int6 = ptrtoint ptr %base5 to i64
  %int.to.ptr7 = inttoptr i64 %ptr.to.int6 to ptr
  store ptr %int.to.ptr7, ptr %reference, align 8
  store i1 true, ptr %needs.deinit1, align 1
  %1 = load ptr, ptr %reference, align 8
  %2 = insertvalue { ptr } undef, ptr %1, 0
  ret { ptr } %2
}

declare { { ptr, i64 } } @"string_hash_map_key_view__f40__in_s{key:pro_s{data:pro_u8,length:unative}}__out_s{view:s{data:pro_u8,length:unative}}"({ ptr })

declare { { ptr, i64 } } @"string_hash_map_key_view__f41__in_s{key:pro_char}__out_s{view:s{data:pro_u8,length:unative}}"({ ptr })

declare { ptr } @"reinterpret_reference__f164__in_s{base:pro_char}__out_s{reference:pro_u8}"({ ptr })

declare { i64 } @"c_string_length__f30__in_s{text:pro_char}__out_s{length:unative}"({ ptr })

declare { { ptr, i64 } } @"string_hash_map_key_view__f42__in_s{key:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{view:s{data:pro_u8,length:unative}}"({ ptr })

declare { { ptr, i64 } } @"as_view__f73__in_s{self:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{view:s{data:pro_u8,length:unative}}"({ ptr })

declare { i64 } @"string_hash_map_hash__f43__in_s{key:pro_s{data:pro_u8,length:unative}}__out_s{hash:unative}"({ ptr })

declare { i8 } @"bytes_get__f63__in_s{view:pro_s{data:pro_u8,length:unative},index:unative}__out_s{byte:u8}"({ ptr, i64 })

declare { i64 } @"string_hash_map_bucket_index__f44__in_s{bucket_count:unative,key:pro_s{data:pro_u8,length:unative}}__out_s{index:unative}"({ i64, ptr })

define {} @"init__f45__in_s{p:prw_s{}}__out_s{}"({ ptr } %0) {
entry:
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %p, align 8
  ret {} undef
}

define { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"allocate__f46__in_s{self:prw_s{},size:unative}__out_s{result:choice}"({ ptr, i64 } %0) {
entry:
  %allocation = alloca { ptr, i64, { ptr, ptr } }, align 8
  %needs.deinit24 = alloca i1, align 1
  %needs.deinit25 = alloca i1, align 1
  %needs.deinit26 = alloca i1, align 1
  %needs.deinit27 = alloca i1, align 1
  %needs.deinit28 = alloca i1, align 1
  %needs.deinit29 = alloca i1, align 1
  %deallocator = alloca { ptr, ptr }, align 8
  %needs.deinit14 = alloca i1, align 1
  %needs.deinit15 = alloca i1, align 1
  %needs.deinit16 = alloca i1, align 1
  %address = alloca i64, align 8
  %needs.deinit8 = alloca i1, align 1
  %physical_size = alloca i64, align 8
  %needs.deinit5 = alloca i1, align 1
  %result = alloca { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, align 8
  %needs.deinit3 = alloca i1, align 1
  %size = alloca i64, align 8
  %needs.deinit1 = alloca i1, align 1
  %self = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  %arg = extractvalue { ptr, i64 } %0, 0
  store ptr %arg, ptr %self, align 8
  %arg2 = extractvalue { ptr, i64 } %0, 1
  store i64 %arg2, ptr %size, align 4
  store i1 false, ptr %needs.deinit3, align 1
  %size4 = load i64, ptr %size, align 4
  store i1 true, ptr %needs.deinit5, align 1
  store i64 %size4, ptr %physical_size, align 4
  %physical_size6 = load i64, ptr %physical_size, align 4
  %ieq = icmp eq i64 %physical_size6, 0
  br i1 %ieq, label %then, label %ifend

then:                                             ; preds = %entry
  store i64 1, ptr %physical_size, align 4
  store i1 true, ptr %needs.deinit5, align 1
  br label %ifend

ifend:                                            ; preds = %then, %entry
  %physical_size7 = load i64, ptr %physical_size, align 4
  %lit.insert = insertvalue { i64 } undef, i64 %physical_size7, 0
  %1 = extractvalue { i64 } %lit.insert, 0
  %call = call ptr @malloc(i64 %1)
  %raw.address = ptrtoint ptr %call to i64
  store i1 true, ptr %needs.deinit8, align 1
  store i64 %raw.address, ptr %address, align 4
  %address9 = load i64, ptr %address, align 4
  %ieq10 = icmp eq i64 %address9, 0
  br i1 %ieq10, label %then11, label %ifend12

then11:                                           ; preds = %ifend
  store { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 1, { ptr, i64, { ptr, ptr } } undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } { { i32, i8 } { i32 0, i8 undef }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } { { { ptr, i64, { ptr, ptr } }, i64, i64 } { { ptr, i64, { ptr, ptr } } { ptr null, i64 0, { ptr, ptr } undef }, i64 0, i64 0 } } } }, ptr %result, align 8
  store i1 true, ptr %needs.deinit3, align 1
  %2 = load { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %result, align 8
  %3 = insertvalue { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } undef, { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %2, 0
  ret { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %3

ifend12:                                          ; preds = %ifend
  %self13 = load ptr, ptr %self, align 8
  %virtual.data = insertvalue { ptr, ptr } undef, ptr %self13, 0
  %virtual.vtable = insertvalue { ptr, ptr } %virtual.data, ptr @__argi_vtable_0, 1
  store i1 true, ptr %needs.deinit14, align 1
  store i1 true, ptr %needs.deinit15, align 1
  store i1 true, ptr %needs.deinit16, align 1
  store { ptr, ptr } %virtual.vtable, ptr %deallocator, align 8
  %address17 = load i64, ptr %address, align 4
  %size18 = load i64, ptr %size, align 4
  %deallocator19 = load { ptr, ptr }, ptr %deallocator, align 8
  %lit.insert20 = insertvalue { i64, i64, { ptr, ptr } } undef, i64 %address17, 0
  %lit.insert21 = insertvalue { i64, i64, { ptr, ptr } } %lit.insert20, i64 %size18, 1
  %lit.insert22 = insertvalue { i64, i64, { ptr, ptr } } %lit.insert21, { ptr, ptr } %deallocator19, 2
  %call23 = call { { ptr, i64, { ptr, ptr } } } @"establish_allocation__f48__in_s{storage:unative,size:unative,deallocator:s{data:prw_any,vtable:pro_any}}__out_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}}}"({ i64, i64, { ptr, ptr } } %lit.insert22)
  %call.unpack = extractvalue { { ptr, i64, { ptr, ptr } } } %call23, 0
  store i1 true, ptr %needs.deinit24, align 1
  store i1 true, ptr %needs.deinit25, align 1
  store i1 true, ptr %needs.deinit26, align 1
  store i1 true, ptr %needs.deinit27, align 1
  store i1 true, ptr %needs.deinit28, align 1
  store i1 true, ptr %needs.deinit29, align 1
  store { ptr, i64, { ptr, ptr } } %call.unpack, ptr %allocation, align 8
  %allocation30 = load { ptr, i64, { ptr, ptr } }, ptr %allocation, align 8
  store i1 false, ptr %needs.deinit24, align 1
  store i1 false, ptr %needs.deinit25, align 1
  store i1 false, ptr %needs.deinit26, align 1
  store i1 false, ptr %needs.deinit27, align 1
  store i1 false, ptr %needs.deinit28, align 1
  store i1 false, ptr %needs.deinit29, align 1
  %choice.payload = insertvalue { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 0, { ptr, i64, { ptr, ptr } } undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } undef }, { ptr, i64, { ptr, ptr } } %allocation30, 1
  store { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %choice.payload, ptr %result, align 8
  store i1 true, ptr %needs.deinit3, align 1
  %4 = load { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %result, align 8
  %5 = insertvalue { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } undef, { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %4, 0
  ret { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %5
}

define {} @"deallocate__f47__in_s{self:prw_s{},data:prw_u8,size:unative}__out_s{}"({ ptr, ptr, i64 } %0) {
entry:
  %raw_addr = alloca i64, align 8
  %needs.deinit8 = alloca i1, align 1
  %size = alloca i64, align 8
  %needs.deinit2 = alloca i1, align 1
  %data = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %self = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  store i1 false, ptr %needs.deinit2, align 1
  %arg = extractvalue { ptr, ptr, i64 } %0, 0
  store ptr %arg, ptr %self, align 8
  %arg3 = extractvalue { ptr, ptr, i64 } %0, 1
  store ptr %arg3, ptr %data, align 8
  %arg4 = extractvalue { ptr, ptr, i64 } %0, 2
  store i64 %arg4, ptr %size, align 4
  %data5 = load ptr, ptr %data, align 8
  %ptr.to.int = ptrtoint ptr %data5 to i64
  %data6 = load ptr, ptr %data, align 8
  %ptr.to.int7 = ptrtoint ptr %data6 to i64
  store i1 true, ptr %needs.deinit8, align 1
  store i64 %ptr.to.int7, ptr %raw_addr, align 4
  %raw_addr9 = load i64, ptr %raw_addr, align 4
  %lit.insert = insertvalue { i64 } undef, i64 %raw_addr9, 0
  %1 = extractvalue { i64 } %lit.insert, 0
  %free.address = inttoptr i64 %1 to ptr
  call void @free(ptr %free.address)
  ret {} undef
}

define { { ptr, i64, { ptr, ptr } } } @"establish_allocation__f48__in_s{storage:unative,size:unative,deallocator:s{data:prw_any,vtable:pro_any}}__out_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}}}"({ i64, i64, { ptr, ptr } } %0) {
entry:
  %data = alloca ptr, align 8
  %needs.deinit16 = alloca i1, align 1
  %allocation = alloca { ptr, i64, { ptr, ptr } }, align 8
  %needs.deinit7 = alloca i1, align 1
  %needs.deinit8 = alloca i1, align 1
  %needs.deinit9 = alloca i1, align 1
  %needs.deinit10 = alloca i1, align 1
  %needs.deinit11 = alloca i1, align 1
  %needs.deinit12 = alloca i1, align 1
  %deallocator = alloca { ptr, ptr }, align 8
  %needs.deinit2 = alloca i1, align 1
  %needs.deinit3 = alloca i1, align 1
  %needs.deinit4 = alloca i1, align 1
  %size = alloca i64, align 8
  %needs.deinit1 = alloca i1, align 1
  %storage = alloca i64, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  store i1 false, ptr %needs.deinit2, align 1
  store i1 false, ptr %needs.deinit3, align 1
  store i1 false, ptr %needs.deinit4, align 1
  %arg = extractvalue { i64, i64, { ptr, ptr } } %0, 0
  store i64 %arg, ptr %storage, align 4
  %arg5 = extractvalue { i64, i64, { ptr, ptr } } %0, 1
  store i64 %arg5, ptr %size, align 4
  %arg6 = extractvalue { i64, i64, { ptr, ptr } } %0, 2
  store { ptr, ptr } %arg6, ptr %deallocator, align 8
  store i1 false, ptr %needs.deinit7, align 1
  store i1 false, ptr %needs.deinit8, align 1
  store i1 false, ptr %needs.deinit9, align 1
  store i1 false, ptr %needs.deinit10, align 1
  store i1 false, ptr %needs.deinit11, align 1
  store i1 false, ptr %needs.deinit12, align 1
  %storage13 = load i64, ptr %storage, align 4
  %int.to.ptr = inttoptr i64 %storage13 to ptr
  %storage14 = load i64, ptr %storage, align 4
  %int.to.ptr15 = inttoptr i64 %storage14 to ptr
  store i1 true, ptr %needs.deinit16, align 1
  store ptr %int.to.ptr15, ptr %data, align 8
  %data17 = load ptr, ptr %data, align 8
  %size18 = load i64, ptr %size, align 4
  %deallocator19 = load { ptr, ptr }, ptr %deallocator, align 8
  %lit.insert = insertvalue { ptr, i64, { ptr, ptr } } undef, ptr %data17, 0
  %lit.insert20 = insertvalue { ptr, i64, { ptr, ptr } } %lit.insert, i64 %size18, 1
  %lit.insert21 = insertvalue { ptr, i64, { ptr, ptr } } %lit.insert20, { ptr, ptr } %deallocator19, 2
  store { ptr, i64, { ptr, ptr } } %lit.insert21, ptr %allocation, align 8
  store i1 true, ptr %needs.deinit7, align 1
  store i1 true, ptr %needs.deinit8, align 1
  store i1 true, ptr %needs.deinit9, align 1
  store i1 true, ptr %needs.deinit10, align 1
  store i1 true, ptr %needs.deinit11, align 1
  store i1 true, ptr %needs.deinit12, align 1
  %1 = load { ptr, i64, { ptr, ptr } }, ptr %allocation, align 8
  %2 = insertvalue { { ptr, i64, { ptr, ptr } } } undef, { ptr, i64, { ptr, ptr } } %1, 0
  ret { { ptr, i64, { ptr, ptr } } } %2
}

define {} @"deinit__f49__in_s{self:prw_s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}}}__out_s{}"({ ptr } %0) {
entry:
  %self = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %self, align 8
  %self1 = load ptr, ptr %self, align 8
  %field.addr = getelementptr inbounds nuw { ptr, i64, { ptr, ptr } }, ptr %self1, i32 0, i32 2
  %virtual.data.addr = getelementptr inbounds nuw { ptr, ptr }, ptr %field.addr, i32 0, i32 0
  %virtual.vtable.addr = getelementptr inbounds nuw { ptr, ptr }, ptr %field.addr, i32 0, i32 1
  %virtual.data = load ptr, ptr %virtual.data.addr, align 8
  %virtual.vtable = load ptr, ptr %virtual.vtable.addr, align 8
  %virtual.method.addr = getelementptr inbounds nuw { ptr }, ptr %virtual.vtable, i32 0, i32 0
  %virtual.method = load ptr, ptr %virtual.method.addr, align 8
  %virtual.arg = insertvalue { ptr, ptr, i64 } undef, ptr %virtual.data, 0
  %self2 = load ptr, ptr %self, align 8
  %deref = load { ptr, i64, { ptr, ptr } }, ptr %self2, align 8
  %fld = extractvalue { ptr, i64, { ptr, ptr } } %deref, 0
  %virtual.arg3 = insertvalue { ptr, ptr, i64 } %virtual.arg, ptr %fld, 1
  %self4 = load ptr, ptr %self, align 8
  %deref5 = load { ptr, i64, { ptr, ptr } }, ptr %self4, align 8
  %fld6 = extractvalue { ptr, i64, { ptr, ptr } } %deref5, 1
  %virtual.arg7 = insertvalue { ptr, ptr, i64 } %virtual.arg3, i64 %fld6, 2
  %virtual.call = call {} %virtual.method({ ptr, ptr, i64 } %virtual.arg7)
  ret {} undef
}

declare {} @"init__f50__in_s{p:prw_s{marker:bool}}__out_s{}"({ ptr })

declare {} @"deinit__f51__in_s{self:prw_s{marker:bool}}__out_s{}"({ ptr })

declare { i64 } @"arena_min_block_capacity__f23__in_s{requested:unative,block_size:unative}__out_s{capacity:unative}"({ i64, i64 })

declare { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"init__f52__in_s{p:prw_s{backing_allocator:prw_s{},blocks:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},domain:s{marker:bool},block_size:unative,current_block_offset:unative},backing_allocator:prw_s{},block_size:unative}__out_s{result:choice}"({ ptr, ptr, i64 })

declare { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"init__f165__in_s{p:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},allocator:prw_s{},capacity:unative}__out_s{result:choice}"({ ptr, ptr, i64 })

declare {} @"arena_free_blocks__f53__in_s{self:prw_s{backing_allocator:prw_s{},blocks:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},domain:s{marker:bool},block_size:unative,current_block_offset:unative}}__out_s{}"({ ptr })

declare { ptr } @"operator get_ro_pointer[]__f166__in_s{self:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},index:unative}__out_s{value:pro_s{data:prw_u8,size:unative}}"({ ptr, i64 })

define {} @"trusted_opaque_mark_empty__f170__in_s{storage:prw_s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}}}__out_s{}"({ ptr } %0) {
entry:
  %storage = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %storage, align 8
  ret {} undef
}

declare {} @"reset__f54__in_s{self:prw_s{backing_allocator:prw_s{},blocks:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},domain:s{marker:bool},block_size:unative,current_block_offset:unative}}__out_s{}"({ ptr })

declare {} @"deinit__f55__in_s{self:prw_s{backing_allocator:prw_s{},blocks:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},domain:s{marker:bool},block_size:unative,current_block_offset:unative}}__out_s{}"({ ptr })

declare {} @"deinit__f171__in_s{allocator:prw_s{},self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative}}__out_s{}"({ ptr, ptr })

declare { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"allocate__f56__in_s{self:prw_s{backing_allocator:prw_s{},blocks:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},domain:s{marker:bool},block_size:unative,current_block_offset:unative},size:unative}__out_s{result:choice}"({ ptr, i64 })

declare { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"ensure_capacity__f176__in_s{allocator:prw_s{},self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},capacity:unative}__out_s{result:choice}"({ ptr, ptr, i64 })

declare { ptr } @"establish_inherited_storage__f179__in_s{address:unative,root:prw_any}__out_s{reference:prw_u8}"({ i64, ptr })

declare {} @"push_assume_capacity__f180__in_s{self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},value:s{data:prw_u8,size:unative}}__out_s{}"({ ptr, { ptr, i64 } })

define { ptr } @"mutable_reference_offset__f182__in_s{base:prw_u8,elements:unative}__out_s{reference:prw_u8}"({ ptr, i64 } %0) {
entry:
  %address = alloca i64, align 8
  %needs.deinit15 = alloca i1, align 1
  %reference = alloca ptr, align 8
  %needs.deinit3 = alloca i1, align 1
  %elements = alloca i64, align 8
  %needs.deinit1 = alloca i1, align 1
  %base = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  %arg = extractvalue { ptr, i64 } %0, 0
  store ptr %arg, ptr %base, align 8
  %arg2 = extractvalue { ptr, i64 } %0, 1
  store i64 %arg2, ptr %elements, align 4
  store i1 false, ptr %needs.deinit3, align 1
  %base4 = load ptr, ptr %base, align 8
  %ptr.to.int = ptrtoint ptr %base4 to i64
  %elements5 = load i64, ptr %elements, align 4
  %mul = mul i64 %elements5, 1
  %base6 = load ptr, ptr %base, align 8
  %ptr.to.int7 = ptrtoint ptr %base6 to i64
  %elements8 = load i64, ptr %elements, align 4
  %mul9 = mul i64 %elements8, 1
  %add = add i64 %ptr.to.int7, %mul9
  %base10 = load ptr, ptr %base, align 8
  %ptr.to.int11 = ptrtoint ptr %base10 to i64
  %elements12 = load i64, ptr %elements, align 4
  %mul13 = mul i64 %elements12, 1
  %add14 = add i64 %ptr.to.int11, %mul13
  store i1 true, ptr %needs.deinit15, align 1
  store i64 %add14, ptr %address, align 4
  %address16 = load i64, ptr %address, align 4
  %int.to.ptr = inttoptr i64 %address16 to ptr
  %address17 = load i64, ptr %address, align 4
  %int.to.ptr18 = inttoptr i64 %address17 to ptr
  store ptr %int.to.ptr18, ptr %reference, align 8
  store i1 true, ptr %needs.deinit3, align 1
  %1 = load ptr, ptr %reference, align 8
  %2 = insertvalue { ptr } undef, ptr %1, 0
  ret { ptr } %2
}

declare { { i64 } } @"raw_pointer__f183__in_s{address:unative}__out_s{raw:s{address:unative}}"({ i64 })

declare { ptr } @"establish_inherited_reference__f184__in_s{raw:s{address:unative},root:prw_any}__out_s{reference:prw_u8}"({ { i64 }, ptr })

define {} @"deallocate__f57__in_s{self:prw_s{backing_allocator:prw_s{},blocks:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},domain:s{marker:bool},block_size:unative,current_block_offset:unative},data:prw_u8,size:unative}__out_s{}"({ ptr, ptr, i64 } %0) {
entry:
  %size = alloca i64, align 8
  %needs.deinit2 = alloca i1, align 1
  %data = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %self = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  store i1 false, ptr %needs.deinit2, align 1
  %arg = extractvalue { ptr, ptr, i64 } %0, 0
  store ptr %arg, ptr %self, align 8
  %arg3 = extractvalue { ptr, ptr, i64 } %0, 1
  store ptr %arg3, ptr %data, align 8
  %arg4 = extractvalue { ptr, ptr, i64 } %0, 2
  store i64 %arg4, ptr %size, align 4
  ret {} undef
}

declare { i64 } @"page_allocator_page_size__f58__in_s{self:prw_s{page_size:unative}}__out_s{size:unative}"({ ptr })

declare { i64 } @"page_allocator_round_up__f24__in_s{size:unative,alignment:unative}__out_s{rounded:unative}"({ i64, i64 })

declare {} @"init__f59__in_s{p:prw_s{page_size:unative}}__out_s{}"({ ptr })

declare { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"allocate__f60__in_s{self:prw_s{page_size:unative},size:unative}__out_s{result:choice}"({ ptr, i64 })

define {} @"deallocate__f61__in_s{self:prw_s{page_size:unative},data:prw_u8,size:unative}__out_s{}"({ ptr, ptr, i64 } %0) {
entry:
  %size = alloca i64, align 8
  %needs.deinit2 = alloca i1, align 1
  %data = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %self = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  store i1 false, ptr %needs.deinit2, align 1
  %arg = extractvalue { ptr, ptr, i64 } %0, 0
  store ptr %arg, ptr %self, align 8
  %arg3 = extractvalue { ptr, ptr, i64 } %0, 1
  store ptr %arg3, ptr %data, align 8
  %arg4 = extractvalue { ptr, ptr, i64 } %0, 2
  store i64 %arg4, ptr %size, align 4
  %data5 = load ptr, ptr %data, align 8
  %ptr.to.int = ptrtoint ptr %data5 to i64
  %data6 = load ptr, ptr %data, align 8
  %ptr.to.int7 = ptrtoint ptr %data6 to i64
  %lit.insert = insertvalue { i64 } undef, i64 %ptr.to.int7, 0
  %1 = extractvalue { i64 } %lit.insert, 0
  %free.address = inttoptr i64 %1 to ptr
  call void @free(ptr %free.address)
  ret {} undef
}

declare { ptr } @"string_view_byte_address__f62__in_s{self:pro_s{data:pro_u8,length:unative},index:unative}__out_s{reference:pro_u8}"({ ptr, i64 })

declare { ptr } @"reference_offset__f185__in_s{base:pro_u8,elements:unative}__out_s{reference:pro_u8}"({ ptr, i64 })

declare { i1 } @"equals__f64__in_s{left:s{data:pro_u8,length:unative},right:s{data:pro_u8,length:unative}}__out_s{ok:bool}"({ { ptr, i64 }, { ptr, i64 } })

declare { i1 } @"operator ==__f65__in_s{left:s{data:pro_u8,length:unative},right:s{data:pro_u8,length:unative}}__out_s{ok:bool}"({ { ptr, i64 }, { ptr, i64 } })

declare { i1 } @"operator !=__f66__in_s{left:s{data:pro_u8,length:unative},right:s{data:pro_u8,length:unative}}__out_s{ok:bool}"({ { ptr, i64 }, { ptr, i64 } })

declare { ptr } @"from_literal__f25__in_s{data:pro_char}__out_s{text:pro_char}"({ ptr })

declare { ptr } @"as_c_string__f67__in_s{self:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{text:pro_char}"({ ptr })

declare { ptr } @"reinterpret_reference__f186__in_s{base:prw_u8}__out_s{reference:pro_char}"({ ptr })

declare { i1 } @"string_view_has_c_string_layout__f68__in_s{self:pro_s{data:pro_u8,length:unative}}__out_s{ok:bool}"({ ptr })

declare { { ptr, i64 } } @"as_view__f69__in_s{self:pro_char}__out_s{view:s{data:pro_u8,length:unative}}"({ ptr })

declare { i8 } @"decimal_digit_byte__f26__in_s{digit:u64}__out_s{byte:u8}"({ i64 })

declare { i8 } @"decimal_digit_byte_u32__f27__in_s{digit:u32}__out_s{byte:u8}"({ i32 })

declare { i8 } @"decimal_digit_byte__f28__in_s{digit:i64}__out_s{byte:u8}"({ i64 })

declare { i8 } @"decimal_digit_byte_i32__f29__in_s{digit:i32}__out_s{byte:u8}"({ i32 })

declare { ptr } @"string_byte_reference__f70__in_s{string:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},index:unative}__out_s{reference:pro_u8}"({ ptr, i64 })

declare { ptr } @"reference_offset__f187__in_s{base:prw_u8,elements:unative}__out_s{reference:pro_u8}"({ ptr, i64 })

declare { i8 } @"bytes_get__f71__in_s{string:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},index:unative}__out_s{byte:u8}"({ ptr, i64 })

define {} @"bytes_set__f72__in_s{string:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},index:unative,value:u8}__out_s{}"({ ptr, i64, i8 } %0) {
entry:
  %ptr = alloca ptr, align 8
  %needs.deinit9 = alloca i1, align 1
  %value = alloca i8, align 1
  %needs.deinit2 = alloca i1, align 1
  %index = alloca i64, align 8
  %needs.deinit1 = alloca i1, align 1
  %string = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  store i1 false, ptr %needs.deinit2, align 1
  %arg = extractvalue { ptr, i64, i8 } %0, 0
  store ptr %arg, ptr %string, align 8
  %arg3 = extractvalue { ptr, i64, i8 } %0, 1
  store i64 %arg3, ptr %index, align 4
  %arg4 = extractvalue { ptr, i64, i8 } %0, 2
  store i8 %arg4, ptr %value, align 1
  %string5 = load ptr, ptr %string, align 8
  %deref = load { { ptr, i64, { ptr, ptr } }, i64 }, ptr %string5, align 8
  %fld = extractvalue { { ptr, i64, { ptr, ptr } }, i64 } %deref, 0
  %fld6 = extractvalue { ptr, i64, { ptr, ptr } } %fld, 0
  %index7 = load i64, ptr %index, align 4
  %lit.insert = insertvalue { ptr, i64 } undef, ptr %fld6, 0
  %lit.insert8 = insertvalue { ptr, i64 } %lit.insert, i64 %index7, 1
  %call = call { ptr } @"mutable_reference_offset__f182__in_s{base:prw_u8,elements:unative}__out_s{reference:prw_u8}"({ ptr, i64 } %lit.insert8)
  %call.unpack = extractvalue { ptr } %call, 0
  store i1 true, ptr %needs.deinit9, align 1
  store ptr %call.unpack, ptr %ptr, align 8
  %ptr10 = load ptr, ptr %ptr, align 8
  %value11 = load i8, ptr %value, align 1
  store i8 %value11, ptr %ptr10, align 1
  ret {} undef
}

define { ptr } @"read_reference__f188__in_s{base:prw_u8}__out_s{reference:pro_u8}"({ ptr } %0) {
entry:
  %reference = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %base = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %base, align 8
  store i1 false, ptr %needs.deinit1, align 1
  %base2 = load ptr, ptr %base, align 8
  %ptr.to.int = ptrtoint ptr %base2 to i64
  %base3 = load ptr, ptr %base, align 8
  %ptr.to.int4 = ptrtoint ptr %base3 to i64
  %int.to.ptr = inttoptr i64 %ptr.to.int4 to ptr
  %base5 = load ptr, ptr %base, align 8
  %ptr.to.int6 = ptrtoint ptr %base5 to i64
  %int.to.ptr7 = inttoptr i64 %ptr.to.int6 to ptr
  store ptr %int.to.ptr7, ptr %reference, align 8
  store i1 true, ptr %needs.deinit1, align 1
  %1 = load ptr, ptr %reference, align 8
  %2 = insertvalue { ptr } undef, ptr %1, 0
  ret { ptr } %2
}

declare { i64 } @"capacity__f74__in_s{self:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{value:unative}"({ ptr })

declare {} @"clear__f75__in_s{self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{}"({ ptr })

declare { i1 } @"has_space__f76__in_s{self:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{ok:bool}"({ ptr })

declare { i64 } @"string_growth_capacity__f77__in_s{self:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},min_capacity:unative}__out_s{value:unative}"({ ptr, i64 })

declare {} @"string_append_byte__f78__in_s{self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},byte:u8}__out_s{}"({ ptr, i8 })

declare {} @"string_append_bytes__f79__in_s{self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},source:s{data:pro_u8,length:unative}}__out_s{}"({ ptr, { ptr, i64 } })

define { { ptr, i64 } } @"array_view__f189__in_s{data:prw_u8,length:unative}__out_s{array:s{data:prw_u8,length:unative}}"({ ptr, i64 } %0) {
entry:
  %array = alloca { ptr, i64 }, align 8
  %needs.deinit3 = alloca i1, align 1
  %needs.deinit4 = alloca i1, align 1
  %needs.deinit5 = alloca i1, align 1
  %length = alloca i64, align 8
  %needs.deinit1 = alloca i1, align 1
  %data = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  %arg = extractvalue { ptr, i64 } %0, 0
  store ptr %arg, ptr %data, align 8
  %arg2 = extractvalue { ptr, i64 } %0, 1
  store i64 %arg2, ptr %length, align 4
  store i1 false, ptr %needs.deinit3, align 1
  store i1 false, ptr %needs.deinit4, align 1
  store i1 false, ptr %needs.deinit5, align 1
  %data6 = load ptr, ptr %data, align 8
  %length7 = load i64, ptr %length, align 4
  %lit.insert = insertvalue { ptr, i64 } undef, ptr %data6, 0
  %lit.insert8 = insertvalue { ptr, i64 } %lit.insert, i64 %length7, 1
  store { ptr, i64 } %lit.insert8, ptr %array, align 8
  store i1 true, ptr %needs.deinit3, align 1
  store i1 true, ptr %needs.deinit4, align 1
  store i1 true, ptr %needs.deinit5, align 1
  %1 = load { ptr, i64 }, ptr %array, align 8
  %2 = insertvalue { { ptr, i64 } } undef, { ptr, i64 } %1, 0
  ret { { ptr, i64 } } %2
}

declare { { ptr, i64 } } @"c_string_as_view__f80__in_s{text:pro_char}__out_s{view:s{data:pro_u8,length:unative}}"({ ptr })

declare { { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"concat_views__f81__in_s{left:pro_s{data:pro_u8,length:unative},right:pro_s{data:pro_u8,length:unative},allocator:prw_s{}}__out_s{result:choice}"({ ptr, ptr, ptr })

declare { { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"string_with_capacity__f190__in_s{allocator:prw_s{},capacity:unative}__out_s{result:choice}"({ ptr, i64 })

define { { ptr, i64 } } @"array_view_ro__f192__in_s{data:pro_u8,length:unative}__out_s{array:s{data:pro_u8,length:unative}}"({ ptr, i64 } %0) {
entry:
  %array = alloca { ptr, i64 }, align 8
  %needs.deinit3 = alloca i1, align 1
  %needs.deinit4 = alloca i1, align 1
  %needs.deinit5 = alloca i1, align 1
  %length = alloca i64, align 8
  %needs.deinit1 = alloca i1, align 1
  %data = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  %arg = extractvalue { ptr, i64 } %0, 0
  store ptr %arg, ptr %data, align 8
  %arg2 = extractvalue { ptr, i64 } %0, 1
  store i64 %arg2, ptr %length, align 4
  store i1 false, ptr %needs.deinit3, align 1
  store i1 false, ptr %needs.deinit4, align 1
  store i1 false, ptr %needs.deinit5, align 1
  %data6 = load ptr, ptr %data, align 8
  %length7 = load i64, ptr %length, align 4
  %lit.insert = insertvalue { ptr, i64 } undef, ptr %data6, 0
  %lit.insert8 = insertvalue { ptr, i64 } %lit.insert, i64 %length7, 1
  store { ptr, i64 } %lit.insert8, ptr %array, align 8
  store i1 true, ptr %needs.deinit3, align 1
  store i1 true, ptr %needs.deinit4, align 1
  store i1 true, ptr %needs.deinit5, align 1
  %1 = load { ptr, i64 }, ptr %array, align 8
  %2 = insertvalue { { ptr, i64 } } undef, { ptr, i64 } %1, 0
  ret { { ptr, i64 } } %2
}

declare { { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"operator +__f82__in_s{left:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},right:pro_char,allocator:prw_s{}}__out_s{result:choice}"({ ptr, ptr, ptr })

declare { { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"operator +__f83__in_s{left:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},right:pro_s{data:pro_u8,length:unative},allocator:prw_s{}}__out_s{result:choice}"({ ptr, ptr, ptr })

declare { { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"operator +__f84__in_s{left:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},right:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},allocator:prw_s{}}__out_s{result:choice}"({ ptr, ptr, ptr })

declare { { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"operator +__f85__in_s{left:pro_s{data:pro_u8,length:unative},right:pro_char,allocator:prw_s{}}__out_s{result:choice}"({ ptr, ptr, ptr })

declare { { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"operator +__f86__in_s{left:pro_s{data:pro_u8,length:unative},right:pro_s{data:pro_u8,length:unative},allocator:prw_s{}}__out_s{result:choice}"({ ptr, ptr, ptr })

declare { { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"operator +__f87__in_s{left:pro_s{data:pro_u8,length:unative},right:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},allocator:prw_s{}}__out_s{result:choice}"({ ptr, ptr, ptr })

define {} @"init__f88__in_s{p:prw_s{}}__out_s{}"({ ptr } %0) {
entry:
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %p, align 8
  ret {} undef
}

define {} @"init__f89__in_s{p:prw_s{count:unative,address:unative}}__out_s{}"({ ptr } %0) {
entry:
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %p, align 8
  %p1 = load ptr, ptr %p, align 8
  %call = call i64 @argi_runtime_argc()
  %call2 = call i64 @argi_runtime_argv()
  %lit.insert = insertvalue { i64, i64 } undef, i64 %call, 0
  %lit.insert3 = insertvalue { i64, i64 } %lit.insert, i64 %call2, 1
  store { i64, i64 } %lit.insert3, ptr %p1, align 4
  ret {} undef
}

declare { i64 } @"length__f90__in_s{self:pro_s{count:unative,address:unative}}__out_s{count:unative}"({ ptr })

declare { i1 } @"has_argument__f91__in_s{self:pro_s{count:unative,address:unative},index:unative}__out_s{ok:bool}"({ ptr, i64 })

declare { i64 } @"argument_pointer_address__f92__in_s{self:pro_s{count:unative,address:unative},index:unative}__out_s{address:unative}"({ ptr, i64 })

declare { ptr } @"argument_at__f93__in_s{self:pro_s{count:unative,address:unative},index:unative}__out_s{text:pro_char}"({ ptr, i64 })

declare { { i64 } } @"raw_pointer__f193__in_s{address:unative}__out_s{raw:s{address:unative}}"({ i64 })

declare { ptr } @"establish_inherited_reference__f194__in_s{raw:s{address:unative},root:pro_any}__out_s{reference:prw_unative}"({ { i64 }, ptr })

declare { { i64 } } @"raw_pointer__f195__in_s{address:unative}__out_s{raw:s{address:unative}}"({ i64 })

declare { ptr } @"establish_inherited_reference__f196__in_s{raw:s{address:unative},root:pro_any}__out_s{reference:prw_char}"({ { i64 }, ptr })

declare { ptr } @"read_reference__f197__in_s{base:prw_char}__out_s{reference:pro_char}"({ ptr })

declare { { ptr, i64 } } @"argument_view_at__f94__in_s{self:pro_s{count:unative,address:unative},index:unative}__out_s{view:s{data:pro_u8,length:unative}}"({ ptr, i64 })

declare { { ptr, i64 } } @"operator get[]__f95__in_s{self:pro_s{count:unative,address:unative},index:unative}__out_s{view:s{data:pro_u8,length:unative}}"({ ptr, i64 })

declare { { ptr, i64 } } @"to_iterator__f96__in_s{value:pro_s{count:unative,address:unative}}__out_s{iterator:s{args:pro_s{count:unative,address:unative},index:unative}}"({ ptr })

declare { i1 } @"has_next__f97__in_s{self:pro_s{args:pro_s{count:unative,address:unative},index:unative}}__out_s{ok:bool}"({ ptr })

declare { { ptr, i64 } } @"next__f98__in_s{self:prw_s{args:pro_s{count:unative,address:unative},index:unative}}__out_s{value:s{data:pro_u8,length:unative}}"({ ptr })

define {} @"init__f99__in_s{p:prw_s{}}__out_s{}"({ ptr } %0) {
entry:
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %p, align 8
  ret {} undef
}

declare { { i32, i8, { { ptr, i64 } } } } @"environment_variables_get_c_string__f100__in_s{key:pro_char}__out_s{value:choice}"({ ptr })

declare { { i32, { i32, i8, { { ptr, i64 } } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"operator get[]__f101__in_s{self:pro_s{},index:s{data:pro_u8,length:unative}}__out_s{result:choice}"({ ptr, { ptr, i64 } })

declare { { i32, { i32, i8, { { ptr, i64 } } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"get__f198__in_s{self:pro_s{},key:s{data:pro_u8,length:unative},allocator:prw_s{}}__out_s{result:choice}"({ ptr, { ptr, i64 }, ptr })

declare {} @"init__f102__in_s{p:prw_s{stream_address:unative,should_close:bool},stream_address:unative,should_close:bool}__out_s{}"({ ptr, i64, i1 })

declare { i1 } @"is_open__f103__in_s{self:pro_s{stream_address:unative,should_close:bool}}__out_s{ok:bool}"({ ptr })

define { ptr } @"file_open_mode_c_string__f33__in_s{mode:choice}__out_s{text:pro_char}"({ { i32, i8, i8, i8 } } %0) {
entry:
  %text = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %mode = alloca { i32, i8, i8, i8 }, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { { i32, i8, i8, i8 } } %0, 0
  store { i32, i8, i8, i8 } %arg, ptr %mode, align 4
  store i1 false, ptr %needs.deinit1, align 1
  %mode2 = load { i32, i8, i8, i8 }, ptr %mode, align 4
  %choice.lhs.tag = extractvalue { i32, i8, i8, i8 } %mode2, 0
  %choice.eq = icmp eq i32 %choice.lhs.tag, 0
  br i1 %choice.eq, label %then, label %ifend

then:                                             ; preds = %entry
  store ptr @argi.strlit.0, ptr %text, align 8
  store i1 true, ptr %needs.deinit1, align 1
  %1 = load ptr, ptr %text, align 8
  %2 = insertvalue { ptr } undef, ptr %1, 0
  ret { ptr } %2

ifend:                                            ; preds = %entry
  %mode3 = load { i32, i8, i8, i8 }, ptr %mode, align 4
  %choice.lhs.tag4 = extractvalue { i32, i8, i8, i8 } %mode3, 0
  %choice.eq5 = icmp eq i32 %choice.lhs.tag4, 1
  br i1 %choice.eq5, label %then6, label %ifend7

then6:                                            ; preds = %ifend
  store ptr @argi.strlit.1, ptr %text, align 8
  store i1 true, ptr %needs.deinit1, align 1
  %3 = load ptr, ptr %text, align 8
  %4 = insertvalue { ptr } undef, ptr %3, 0
  ret { ptr } %4

ifend7:                                           ; preds = %ifend
  store ptr @argi.strlit.2, ptr %text, align 8
  store i1 true, ptr %needs.deinit1, align 1
  %5 = load ptr, ptr %text, align 8
  %6 = insertvalue { ptr } undef, ptr %5, 0
  ret { ptr } %6
}

declare { ptr } @"file_stream_pointer__f104__in_s{self:pro_s{stream_address:unative,should_close:bool}}__out_s{stream:pro_any}"({ ptr })

declare { { i64 } } @"raw_pointer__f201__in_s{address:unative}__out_s{raw:s{address:unative}}"({ i64 })

declare { ptr } @"establish_inherited_reference__f202__in_s{raw:s{address:unative},root:pro_any}__out_s{reference:prw_any}"({ { i64 }, ptr })

declare { ptr } @"read_reference__f203__in_s{base:prw_any}__out_s{reference:pro_any}"({ ptr })

declare { { i32, i1, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"open__f105__in_s{p:prw_s{stream_address:unative,should_close:bool},path:pro_char,mode:choice}__out_s{result:choice}"({ ptr, ptr, { i32, i8, i8, i8 } })

declare { { i32, i1, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"open_read__f106__in_s{p:prw_s{stream_address:unative,should_close:bool},path:pro_char}__out_s{result:choice}"({ ptr, ptr })

declare { { i32, i1, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"open_write__f107__in_s{p:prw_s{stream_address:unative,should_close:bool},path:pro_char}__out_s{result:choice}"({ ptr, ptr })

declare { { i32, i1, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"open_append__f108__in_s{p:prw_s{stream_address:unative,should_close:bool},path:pro_char}__out_s{result:choice}"({ ptr, ptr })

define {} @"init_stdin__f109__in_s{p:prw_s{stream_address:unative,should_close:bool}}__out_s{}"({ ptr } %0) {
entry:
  %stream = alloca ptr, align 8
  %needs.deinit4 = alloca i1, align 1
  %mode_text = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %p, align 8
  %call = call { ptr } @"file_open_mode_c_string__f33__in_s{mode:choice}__out_s{text:pro_char}"({ { i32, i8, i8, i8 } } { { i32, i8, i8, i8 } { i32 0, i8 undef, i8 undef, i8 undef } })
  %call.unpack = extractvalue { ptr } %call, 0
  store i1 true, ptr %needs.deinit1, align 1
  store ptr %call.unpack, ptr %mode_text, align 8
  %mode_text2 = load ptr, ptr %mode_text, align 8
  %lit.insert = insertvalue { i32, ptr } { i32 0, ptr undef }, ptr %mode_text2, 1
  %1 = extractvalue { i32, ptr } %lit.insert, 0
  %2 = extractvalue { i32, ptr } %lit.insert, 1
  %call3 = call ptr @fdopen(i32 %1, ptr %2)
  store i1 true, ptr %needs.deinit4, align 1
  store ptr %call3, ptr %stream, align 8
  %stream5 = load ptr, ptr %stream, align 8
  %ptr.to.int = ptrtoint ptr %stream5 to i64
  %p6 = load ptr, ptr %p, align 8
  %stream7 = load ptr, ptr %stream, align 8
  %ptr.to.int8 = ptrtoint ptr %stream7 to i64
  %lit.insert9 = insertvalue { i64, i1 } undef, i64 %ptr.to.int8, 0
  %lit.insert10 = insertvalue { i64, i1 } %lit.insert9, i1 false, 1
  store { i64, i1 } %lit.insert10, ptr %p6, align 4
  ret {} undef
}

define {} @"init_stdout__f110__in_s{p:prw_s{stream_address:unative,should_close:bool}}__out_s{}"({ ptr } %0) {
entry:
  %stream = alloca ptr, align 8
  %needs.deinit4 = alloca i1, align 1
  %mode_text = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %p, align 8
  %call = call { ptr } @"file_open_mode_c_string__f33__in_s{mode:choice}__out_s{text:pro_char}"({ { i32, i8, i8, i8 } } { { i32, i8, i8, i8 } { i32 1, i8 undef, i8 undef, i8 undef } })
  %call.unpack = extractvalue { ptr } %call, 0
  store i1 true, ptr %needs.deinit1, align 1
  store ptr %call.unpack, ptr %mode_text, align 8
  %mode_text2 = load ptr, ptr %mode_text, align 8
  %lit.insert = insertvalue { i32, ptr } { i32 1, ptr undef }, ptr %mode_text2, 1
  %1 = extractvalue { i32, ptr } %lit.insert, 0
  %2 = extractvalue { i32, ptr } %lit.insert, 1
  %call3 = call ptr @fdopen(i32 %1, ptr %2)
  store i1 true, ptr %needs.deinit4, align 1
  store ptr %call3, ptr %stream, align 8
  %stream5 = load ptr, ptr %stream, align 8
  %ptr.to.int = ptrtoint ptr %stream5 to i64
  %p6 = load ptr, ptr %p, align 8
  %stream7 = load ptr, ptr %stream, align 8
  %ptr.to.int8 = ptrtoint ptr %stream7 to i64
  %lit.insert9 = insertvalue { i64, i1 } undef, i64 %ptr.to.int8, 0
  %lit.insert10 = insertvalue { i64, i1 } %lit.insert9, i1 false, 1
  store { i64, i1 } %lit.insert10, ptr %p6, align 4
  ret {} undef
}

define {} @"init_stderr__f111__in_s{p:prw_s{stream_address:unative,should_close:bool}}__out_s{}"({ ptr } %0) {
entry:
  %stream = alloca ptr, align 8
  %needs.deinit4 = alloca i1, align 1
  %mode_text = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %p, align 8
  %call = call { ptr } @"file_open_mode_c_string__f33__in_s{mode:choice}__out_s{text:pro_char}"({ { i32, i8, i8, i8 } } { { i32, i8, i8, i8 } { i32 1, i8 undef, i8 undef, i8 undef } })
  %call.unpack = extractvalue { ptr } %call, 0
  store i1 true, ptr %needs.deinit1, align 1
  store ptr %call.unpack, ptr %mode_text, align 8
  %mode_text2 = load ptr, ptr %mode_text, align 8
  %lit.insert = insertvalue { i32, ptr } { i32 2, ptr undef }, ptr %mode_text2, 1
  %1 = extractvalue { i32, ptr } %lit.insert, 0
  %2 = extractvalue { i32, ptr } %lit.insert, 1
  %call3 = call ptr @fdopen(i32 %1, ptr %2)
  store i1 true, ptr %needs.deinit4, align 1
  store ptr %call3, ptr %stream, align 8
  %stream5 = load ptr, ptr %stream, align 8
  %ptr.to.int = ptrtoint ptr %stream5 to i64
  %p6 = load ptr, ptr %p, align 8
  %stream7 = load ptr, ptr %stream, align 8
  %ptr.to.int8 = ptrtoint ptr %stream7 to i64
  %lit.insert9 = insertvalue { i64, i1 } undef, i64 %ptr.to.int8, 0
  %lit.insert10 = insertvalue { i64, i1 } %lit.insert9, i1 false, 1
  store { i64, i1 } %lit.insert10, ptr %p6, align 4
  ret {} undef
}

declare { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"close__f112__in_s{self:prw_s{stream_address:unative,should_close:bool}}__out_s{result:choice}"({ ptr })

declare { { i32, {}, { { i32, i8, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"flush__f113__in_s{self:prw_s{stream_address:unative,should_close:bool}}__out_s{result:choice}"({ ptr })

declare { { i32, { i32, i8, i8 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"read_byte__f114__in_s{self:prw_s{stream_address:unative,should_close:bool}}__out_s{result:choice}"({ ptr })

declare { { i32, {}, { { i32, i8, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"write_byte__f115__in_s{self:prw_s{stream_address:unative,should_close:bool},byte:u8}__out_s{result:choice}"({ ptr, i8 })

declare { { i32, i64, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"read__f116__in_s{self:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,length:unative}}__out_s{result:choice}"({ ptr, { ptr, i64 } })

declare { { i32, i64, { { i32, i8, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"write__f117__in_s{self:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,length:unative}}__out_s{result:choice}"({ ptr, { ptr, i64 } })

define {} @"init__f118__in_s{p:prw_s{}}__out_s{}"({ ptr } %0) {
entry:
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %p, align 8
  ret {} undef
}

declare { i1 } @"exists__f119__in_s{self:pro_s{},path:pro_char}__out_s{ok:bool}"({ ptr, ptr })

declare { i1 } @"exists__f120__in_s{self:pro_s{},path:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{ok:bool}"({ ptr, ptr })

declare { i1 } @"exists__f121__in_s{self:pro_s{},path:pro_s{text:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}}__out_s{ok:bool}"({ ptr, ptr })

declare { { i32, i1, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"remove__f122__in_s{self:pro_s{},path:pro_char}__out_s{result:choice}"({ ptr, ptr })

declare { { i32, i1, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"remove__f123__in_s{self:pro_s{},path:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{result:choice}"({ ptr, ptr })

declare { { i32, i1, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"rename__f124__in_s{self:pro_s{},from:pro_char,to:pro_char}__out_s{result:choice}"({ ptr, ptr, ptr })

declare { { i32, i1, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"rename__f125__in_s{self:pro_s{},from:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},to:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{result:choice}"({ ptr, ptr, ptr })

declare { { i32, { i64, i1 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"open_read__f126__in_s{self:pro_s{},path:pro_char}__out_s{result:choice}"({ ptr, ptr })

declare { { i32, { i64, i1 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"open_read__f127__in_s{self:pro_s{},path:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{result:choice}"({ ptr, ptr })

declare { { i32, { i64, i1 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"open_write__f128__in_s{self:pro_s{},path:pro_char}__out_s{result:choice}"({ ptr, ptr })

declare { { i32, { i64, i1 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"open_write__f129__in_s{self:pro_s{},path:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{result:choice}"({ ptr, ptr })

declare { { i32, { i64, i1 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"open_append__f130__in_s{self:pro_s{},path:pro_char}__out_s{result:choice}"({ ptr, ptr })

declare { { i32, { i64, i1 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"open_append__f131__in_s{self:pro_s{},path:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{result:choice}"({ ptr, ptr })

declare { { i32, {}, { { i32, i8, i8, i8, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"write_file__f132__in_s{self:pro_s{},path:pro_char,text:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{result:choice}"({ ptr, ptr, ptr })

declare { { i32, {}, { { i32, i8, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"write__f204__in_s{self:prw_s{stream_address:unative,should_close:bool},text:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{result:choice}"({ ptr, ptr })

declare { { i32, {}, { { i32, i8, i8, i8, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"write_file__f133__in_s{self:pro_s{},path:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},text:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{result:choice}"({ ptr, ptr, ptr })

declare { i1 } @"path_is_separator__f34__in_s{byte:u8}__out_s{ok:bool}"({ i8 })

declare { { i32, i8, { i64 } } } @"path_last_separator_index__f134__in_s{view:pro_s{data:pro_u8,length:unative}}__out_s{value:choice}"({ ptr })

declare { { ptr, i64 } } @"string_view_slice__f135__in_s{view:pro_s{data:pro_u8,length:unative},start:unative,length:unative}__out_s{out:s{data:pro_u8,length:unative}}"({ ptr, i64, i64 })

declare {} @"init__f136__in_s{p:prw_s{text:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}},text:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{}"({ ptr, { { ptr, i64, { ptr, ptr } }, i64 } })

declare { { ptr, i64 } } @"as_view__f137__in_s{self:pro_s{text:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}}__out_s{view:s{data:pro_u8,length:unative}}"({ ptr })

declare { ptr } @"as_c_string__f138__in_s{self:pro_s{text:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}}__out_s{text:pro_char}"({ ptr })

declare { i1 } @"is_absolute__f139__in_s{self:pro_s{text:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}}__out_s{ok:bool}"({ ptr })

declare { { i32, i8, { { ptr, i64 } } } } @"file_name__f140__in_s{self:pro_s{text:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}}__out_s{value:choice}"({ ptr })

declare { { i32, i8, { { ptr, i64 } } } } @"parent__f141__in_s{self:pro_s{text:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}}__out_s{value:choice}"({ ptr })

declare { { i32, i8, { { ptr, i64 } } } } @"extension__f142__in_s{self:pro_s{text:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}}__out_s{value:choice}"({ ptr })

declare { i1 } @"operator ==__f143__in_s{left:pro_s{text:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}},right:pro_s{text:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}}__out_s{ok:bool}"({ ptr, ptr })

declare { i1 } @"path_equals__f144__in_s{left:pro_s{text:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}},right:pro_s{text:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}}__out_s{ok:bool}"({ ptr, ptr })

define {} @"init__f145__in_s{p:prw_s{}}__out_s{}"({ ptr } %0) {
entry:
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %p, align 8
  ret {} undef
}

define {} @"init__f146__in_s{p:prw_s{}}__out_s{}"({ ptr } %0) {
entry:
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %p, align 8
  ret {} undef
}

define {} @"init__f147__in_s{p:prw_s{_storage:s{allocator:s{},terminal:s{_storage:s{stdin_file:s{stream_address:unative,should_close:bool},stdout_file:s{stream_address:unative,should_close:bool},stderr_file:s{stream_address:unative,should_close:bool},stdin_reader:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative}},stdin_file:prw_s{stream_address:unative,should_close:bool},stdout_file:prw_s{stream_address:unative,should_close:bool},stderr_file:prw_s{stream_address:unative,should_close:bool},stdin_reader:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stdin:prw_abs_Reader,stdout:prw_abs_Writer,stderr:prw_abs_Writer},args:s{count:unative,address:unative},env_vars:s{},file_sys:s{},network:s{},proc_man:s{},clock:s{},rand_gen:s{},ffi:s{}},allocator:prw_s{},terminal:prw_s{_storage:s{stdin_file:s{stream_address:unative,should_close:bool},stdout_file:s{stream_address:unative,should_close:bool},stderr_file:s{stream_address:unative,should_close:bool},stdin_reader:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative}},stdin_file:prw_s{stream_address:unative,should_close:bool},stdout_file:prw_s{stream_address:unative,should_close:bool},stderr_file:prw_s{stream_address:unative,should_close:bool},stdin_reader:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stdin:prw_abs_Reader,stdout:prw_abs_Writer,stderr:prw_abs_Writer},args:prw_s{count:unative,address:unative},env_vars:prw_s{},file_sys:prw_s{},network:prw_s{},proc_man:prw_s{},clock:prw_s{},rand_gen:prw_s{},ffi:prw_s{}}}__out_s{}"({ ptr } %0) {
entry:
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %p, align 8
  %p1 = load ptr, ptr %p, align 8
  %field.addr = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p1, i32 0, i32 0
  %field.ptr = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr, i32 0, i32 0
  %ctor.arg.p = insertvalue { ptr } undef, ptr %field.ptr, 0
  %call = call {} @"init__f45__in_s{p:prw_s{}}__out_s{}"({ ptr } %ctor.arg.p)
  %p2 = load ptr, ptr %p, align 8
  %field.addr3 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p2, i32 0, i32 0
  %field.ptr4 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr3, i32 0, i32 1
  %p5 = load ptr, ptr %p, align 8
  %field.addr6 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p5, i32 0, i32 0
  %field.addr7 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr6, i32 0, i32 0
  %lit.insert = insertvalue { ptr } undef, ptr %field.addr7, 0
  %ctor.arg.p8 = insertvalue { ptr, ptr } undef, ptr %field.ptr4, 0
  %ctor.arg.extract = extractvalue { ptr } %lit.insert, 0
  %ctor.arg.insert = insertvalue { ptr, ptr } %ctor.arg.p8, ptr %ctor.arg.extract, 1
  %call9 = call {} @"init__f149__in_s{p:prw_s{_storage:s{stdin_file:s{stream_address:unative,should_close:bool},stdout_file:s{stream_address:unative,should_close:bool},stderr_file:s{stream_address:unative,should_close:bool},stdin_reader:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative}},stdin_file:prw_s{stream_address:unative,should_close:bool},stdout_file:prw_s{stream_address:unative,should_close:bool},stderr_file:prw_s{stream_address:unative,should_close:bool},stdin_reader:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stdin:prw_abs_Reader,stdout:prw_abs_Writer,stderr:prw_abs_Writer},allocator:prw_s{}}__out_s{}"({ ptr, ptr } %ctor.arg.insert)
  %p10 = load ptr, ptr %p, align 8
  %field.addr11 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p10, i32 0, i32 0
  %field.ptr12 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr11, i32 0, i32 2
  %ctor.arg.p13 = insertvalue { ptr } undef, ptr %field.ptr12, 0
  %call14 = call {} @"init__f89__in_s{p:prw_s{count:unative,address:unative}}__out_s{}"({ ptr } %ctor.arg.p13)
  %p15 = load ptr, ptr %p, align 8
  %field.addr16 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p15, i32 0, i32 0
  %field.ptr17 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr16, i32 0, i32 3
  %ctor.arg.p18 = insertvalue { ptr } undef, ptr %field.ptr17, 0
  %call19 = call {} @"init__f99__in_s{p:prw_s{}}__out_s{}"({ ptr } %ctor.arg.p18)
  %p20 = load ptr, ptr %p, align 8
  %field.addr21 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p20, i32 0, i32 0
  %field.ptr22 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr21, i32 0, i32 4
  %ctor.arg.p23 = insertvalue { ptr } undef, ptr %field.ptr22, 0
  %call24 = call {} @"init__f118__in_s{p:prw_s{}}__out_s{}"({ ptr } %ctor.arg.p23)
  %p25 = load ptr, ptr %p, align 8
  %field.addr26 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p25, i32 0, i32 0
  %field.ptr27 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr26, i32 0, i32 5
  %ctor.arg.p28 = insertvalue { ptr } undef, ptr %field.ptr27, 0
  %call29 = call {} @"init__f145__in_s{p:prw_s{}}__out_s{}"({ ptr } %ctor.arg.p28)
  %p30 = load ptr, ptr %p, align 8
  %field.addr31 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p30, i32 0, i32 0
  %field.ptr32 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr31, i32 0, i32 6
  %ctor.arg.p33 = insertvalue { ptr } undef, ptr %field.ptr32, 0
  %call34 = call {} @"init__f146__in_s{p:prw_s{}}__out_s{}"({ ptr } %ctor.arg.p33)
  %p35 = load ptr, ptr %p, align 8
  %field.addr36 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p35, i32 0, i32 0
  %field.ptr37 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr36, i32 0, i32 7
  %ctor.arg.p38 = insertvalue { ptr } undef, ptr %field.ptr37, 0
  %call39 = call {} @"init__f156__in_s{p:prw_s{}}__out_s{}"({ ptr } %ctor.arg.p38)
  %p40 = load ptr, ptr %p, align 8
  %field.addr41 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p40, i32 0, i32 0
  %field.ptr42 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr41, i32 0, i32 8
  %ctor.arg.p43 = insertvalue { ptr } undef, ptr %field.ptr42, 0
  %call44 = call {} @"init__f88__in_s{p:prw_s{}}__out_s{}"({ ptr } %ctor.arg.p43)
  %p45 = load ptr, ptr %p, align 8
  %field.addr46 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p45, i32 0, i32 0
  %field.ptr47 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr46, i32 0, i32 9
  %ctor.arg.p48 = insertvalue { ptr } undef, ptr %field.ptr47, 0
  %call49 = call {} @"init__f35__in_s{p:prw_s{}}__out_s{}"({ ptr } %ctor.arg.p48)
  %p50 = load ptr, ptr %p, align 8
  %field.ptr51 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p50, i32 0, i32 1
  %p52 = load ptr, ptr %p, align 8
  %field.addr53 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p52, i32 0, i32 0
  %field.addr54 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr53, i32 0, i32 0
  store ptr %field.addr54, ptr %field.ptr51, align 8
  %p55 = load ptr, ptr %p, align 8
  %field.ptr56 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p55, i32 0, i32 2
  %p57 = load ptr, ptr %p, align 8
  %field.addr58 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p57, i32 0, i32 0
  %field.addr59 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr58, i32 0, i32 1
  store ptr %field.addr59, ptr %field.ptr56, align 8
  %p60 = load ptr, ptr %p, align 8
  %field.ptr61 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p60, i32 0, i32 3
  %p62 = load ptr, ptr %p, align 8
  %field.addr63 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p62, i32 0, i32 0
  %field.addr64 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr63, i32 0, i32 2
  store ptr %field.addr64, ptr %field.ptr61, align 8
  %p65 = load ptr, ptr %p, align 8
  %field.ptr66 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p65, i32 0, i32 4
  %p67 = load ptr, ptr %p, align 8
  %field.addr68 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p67, i32 0, i32 0
  %field.addr69 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr68, i32 0, i32 3
  store ptr %field.addr69, ptr %field.ptr66, align 8
  %p70 = load ptr, ptr %p, align 8
  %field.ptr71 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p70, i32 0, i32 5
  %p72 = load ptr, ptr %p, align 8
  %field.addr73 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p72, i32 0, i32 0
  %field.addr74 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr73, i32 0, i32 4
  store ptr %field.addr74, ptr %field.ptr71, align 8
  %p75 = load ptr, ptr %p, align 8
  %field.ptr76 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p75, i32 0, i32 6
  %p77 = load ptr, ptr %p, align 8
  %field.addr78 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p77, i32 0, i32 0
  %field.addr79 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr78, i32 0, i32 5
  store ptr %field.addr79, ptr %field.ptr76, align 8
  %p80 = load ptr, ptr %p, align 8
  %field.ptr81 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p80, i32 0, i32 7
  %p82 = load ptr, ptr %p, align 8
  %field.addr83 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p82, i32 0, i32 0
  %field.addr84 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr83, i32 0, i32 6
  store ptr %field.addr84, ptr %field.ptr81, align 8
  %p85 = load ptr, ptr %p, align 8
  %field.ptr86 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p85, i32 0, i32 8
  %p87 = load ptr, ptr %p, align 8
  %field.addr88 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p87, i32 0, i32 0
  %field.addr89 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr88, i32 0, i32 7
  store ptr %field.addr89, ptr %field.ptr86, align 8
  %p90 = load ptr, ptr %p, align 8
  %field.ptr91 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p90, i32 0, i32 9
  %p92 = load ptr, ptr %p, align 8
  %field.addr93 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p92, i32 0, i32 0
  %field.addr94 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr93, i32 0, i32 8
  store ptr %field.addr94, ptr %field.ptr91, align 8
  %p95 = load ptr, ptr %p, align 8
  %field.ptr96 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p95, i32 0, i32 10
  %p97 = load ptr, ptr %p, align 8
  %field.addr98 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p97, i32 0, i32 0
  %field.addr99 = getelementptr inbounds nuw { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr %field.addr98, i32 0, i32 9
  store ptr %field.addr99, ptr %field.ptr96, align 8
  ret {} undef
}

define {} @"init__f149__in_s{p:prw_s{_storage:s{stdin_file:s{stream_address:unative,should_close:bool},stdout_file:s{stream_address:unative,should_close:bool},stderr_file:s{stream_address:unative,should_close:bool},stdin_reader:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative}},stdin_file:prw_s{stream_address:unative,should_close:bool},stdout_file:prw_s{stream_address:unative,should_close:bool},stderr_file:prw_s{stream_address:unative,should_close:bool},stdin_reader:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stdin:prw_abs_Reader,stdout:prw_abs_Writer,stderr:prw_abs_Writer},allocator:prw_s{}}__out_s{}"({ ptr, ptr } %0) {
entry:
  %allocator = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  %arg = extractvalue { ptr, ptr } %0, 0
  store ptr %arg, ptr %p, align 8
  %arg2 = extractvalue { ptr, ptr } %0, 1
  store ptr %arg2, ptr %allocator, align 8
  %p3 = load ptr, ptr %p, align 8
  %field.addr = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p3, i32 0, i32 0
  %field.addr4 = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr, i32 0, i32 0
  %lit.insert = insertvalue { ptr } undef, ptr %field.addr4, 0
  %call = call {} @"init_stdin__f109__in_s{p:prw_s{stream_address:unative,should_close:bool}}__out_s{}"({ ptr } %lit.insert)
  %p5 = load ptr, ptr %p, align 8
  %field.addr6 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p5, i32 0, i32 0
  %field.addr7 = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr6, i32 0, i32 1
  %lit.insert8 = insertvalue { ptr } undef, ptr %field.addr7, 0
  %call9 = call {} @"init_stdout__f110__in_s{p:prw_s{stream_address:unative,should_close:bool}}__out_s{}"({ ptr } %lit.insert8)
  %p10 = load ptr, ptr %p, align 8
  %field.addr11 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p10, i32 0, i32 0
  %field.addr12 = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr11, i32 0, i32 2
  %lit.insert13 = insertvalue { ptr } undef, ptr %field.addr12, 0
  %call14 = call {} @"init_stderr__f111__in_s{p:prw_s{stream_address:unative,should_close:bool}}__out_s{}"({ ptr } %lit.insert13)
  %p15 = load ptr, ptr %p, align 8
  %field.addr16 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p15, i32 0, i32 0
  %field.ptr = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr16, i32 0, i32 3
  %allocator17 = load ptr, ptr %allocator, align 8
  %p18 = load ptr, ptr %p, align 8
  %field.addr19 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p18, i32 0, i32 0
  %field.addr20 = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr19, i32 0, i32 0
  %lit.insert21 = insertvalue { ptr, ptr, i64 } undef, ptr %allocator17, 0
  %lit.insert22 = insertvalue { ptr, ptr, i64 } %lit.insert21, ptr %field.addr20, 1
  %lit.insert23 = insertvalue { ptr, ptr, i64 } %lit.insert22, i64 256, 2
  %ctor.arg.p = insertvalue { ptr, ptr, ptr, i64 } undef, ptr %field.ptr, 0
  %ctor.arg.extract = extractvalue { ptr, ptr, i64 } %lit.insert23, 0
  %ctor.arg.insert = insertvalue { ptr, ptr, ptr, i64 } %ctor.arg.p, ptr %ctor.arg.extract, 1
  %ctor.arg.extract24 = extractvalue { ptr, ptr, i64 } %lit.insert23, 1
  %ctor.arg.insert25 = insertvalue { ptr, ptr, ptr, i64 } %ctor.arg.insert, ptr %ctor.arg.extract24, 2
  %ctor.arg.extract26 = extractvalue { ptr, ptr, i64 } %lit.insert23, 2
  %ctor.arg.insert27 = insertvalue { ptr, ptr, ptr, i64 } %ctor.arg.insert25, i64 %ctor.arg.extract26, 3
  %call28 = call { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"init__f205__in_s{p:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},allocator:prw_s{},base:prw_s{stream_address:unative,should_close:bool},capacity:unative}__out_s{result:choice}"({ ptr, ptr, ptr, i64 } %ctor.arg.insert27)
  %p29 = load ptr, ptr %p, align 8
  %field.addr30 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p29, i32 0, i32 0
  %field.ptr31 = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr30, i32 0, i32 4
  %allocator32 = load ptr, ptr %allocator, align 8
  %p33 = load ptr, ptr %p, align 8
  %field.addr34 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p33, i32 0, i32 0
  %field.addr35 = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr34, i32 0, i32 1
  %lit.insert36 = insertvalue { ptr, ptr, i64 } undef, ptr %allocator32, 0
  %lit.insert37 = insertvalue { ptr, ptr, i64 } %lit.insert36, ptr %field.addr35, 1
  %lit.insert38 = insertvalue { ptr, ptr, i64 } %lit.insert37, i64 256, 2
  %ctor.arg.p39 = insertvalue { ptr, ptr, ptr, i64 } undef, ptr %field.ptr31, 0
  %ctor.arg.extract40 = extractvalue { ptr, ptr, i64 } %lit.insert38, 0
  %ctor.arg.insert41 = insertvalue { ptr, ptr, ptr, i64 } %ctor.arg.p39, ptr %ctor.arg.extract40, 1
  %ctor.arg.extract42 = extractvalue { ptr, ptr, i64 } %lit.insert38, 1
  %ctor.arg.insert43 = insertvalue { ptr, ptr, ptr, i64 } %ctor.arg.insert41, ptr %ctor.arg.extract42, 2
  %ctor.arg.extract44 = extractvalue { ptr, ptr, i64 } %lit.insert38, 2
  %ctor.arg.insert45 = insertvalue { ptr, ptr, ptr, i64 } %ctor.arg.insert43, i64 %ctor.arg.extract44, 3
  %call46 = call { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"init__f206__in_s{p:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},allocator:prw_s{},base:prw_s{stream_address:unative,should_close:bool},capacity:unative}__out_s{result:choice}"({ ptr, ptr, ptr, i64 } %ctor.arg.insert45)
  %p47 = load ptr, ptr %p, align 8
  %field.addr48 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p47, i32 0, i32 0
  %field.ptr49 = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr48, i32 0, i32 5
  %allocator50 = load ptr, ptr %allocator, align 8
  %p51 = load ptr, ptr %p, align 8
  %field.addr52 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p51, i32 0, i32 0
  %field.addr53 = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr52, i32 0, i32 2
  %lit.insert54 = insertvalue { ptr, ptr, i64 } undef, ptr %allocator50, 0
  %lit.insert55 = insertvalue { ptr, ptr, i64 } %lit.insert54, ptr %field.addr53, 1
  %lit.insert56 = insertvalue { ptr, ptr, i64 } %lit.insert55, i64 256, 2
  %ctor.arg.p57 = insertvalue { ptr, ptr, ptr, i64 } undef, ptr %field.ptr49, 0
  %ctor.arg.extract58 = extractvalue { ptr, ptr, i64 } %lit.insert56, 0
  %ctor.arg.insert59 = insertvalue { ptr, ptr, ptr, i64 } %ctor.arg.p57, ptr %ctor.arg.extract58, 1
  %ctor.arg.extract60 = extractvalue { ptr, ptr, i64 } %lit.insert56, 1
  %ctor.arg.insert61 = insertvalue { ptr, ptr, ptr, i64 } %ctor.arg.insert59, ptr %ctor.arg.extract60, 2
  %ctor.arg.extract62 = extractvalue { ptr, ptr, i64 } %lit.insert56, 2
  %ctor.arg.insert63 = insertvalue { ptr, ptr, ptr, i64 } %ctor.arg.insert61, i64 %ctor.arg.extract62, 3
  %call64 = call { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"init__f206__in_s{p:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},allocator:prw_s{},base:prw_s{stream_address:unative,should_close:bool},capacity:unative}__out_s{result:choice}"({ ptr, ptr, ptr, i64 } %ctor.arg.insert63)
  %p65 = load ptr, ptr %p, align 8
  %field.ptr66 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p65, i32 0, i32 1
  %p67 = load ptr, ptr %p, align 8
  %field.addr68 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p67, i32 0, i32 0
  %field.addr69 = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr68, i32 0, i32 0
  store ptr %field.addr69, ptr %field.ptr66, align 8
  %p70 = load ptr, ptr %p, align 8
  %field.ptr71 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p70, i32 0, i32 2
  %p72 = load ptr, ptr %p, align 8
  %field.addr73 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p72, i32 0, i32 0
  %field.addr74 = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr73, i32 0, i32 1
  store ptr %field.addr74, ptr %field.ptr71, align 8
  %p75 = load ptr, ptr %p, align 8
  %field.ptr76 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p75, i32 0, i32 3
  %p77 = load ptr, ptr %p, align 8
  %field.addr78 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p77, i32 0, i32 0
  %field.addr79 = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr78, i32 0, i32 2
  store ptr %field.addr79, ptr %field.ptr76, align 8
  %p80 = load ptr, ptr %p, align 8
  %field.ptr81 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p80, i32 0, i32 4
  %p82 = load ptr, ptr %p, align 8
  %field.addr83 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p82, i32 0, i32 0
  %field.addr84 = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr83, i32 0, i32 3
  store ptr %field.addr84, ptr %field.ptr81, align 8
  %p85 = load ptr, ptr %p, align 8
  %field.ptr86 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p85, i32 0, i32 5
  %p87 = load ptr, ptr %p, align 8
  %field.addr88 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p87, i32 0, i32 0
  %field.addr89 = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr88, i32 0, i32 4
  store ptr %field.addr89, ptr %field.ptr86, align 8
  %p90 = load ptr, ptr %p, align 8
  %field.ptr91 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p90, i32 0, i32 6
  %p92 = load ptr, ptr %p, align 8
  %field.addr93 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p92, i32 0, i32 0
  %field.addr94 = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr93, i32 0, i32 5
  store ptr %field.addr94, ptr %field.ptr91, align 8
  %p95 = load ptr, ptr %p, align 8
  %field.ptr96 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p95, i32 0, i32 7
  %p97 = load ptr, ptr %p, align 8
  %field.addr98 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p97, i32 0, i32 0
  %field.addr99 = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr98, i32 0, i32 3
  store ptr %field.addr99, ptr %field.ptr96, align 8
  %p100 = load ptr, ptr %p, align 8
  %field.ptr101 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p100, i32 0, i32 8
  %p102 = load ptr, ptr %p, align 8
  %field.addr103 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p102, i32 0, i32 0
  %field.addr104 = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr103, i32 0, i32 4
  store ptr %field.addr104, ptr %field.ptr101, align 8
  %p105 = load ptr, ptr %p, align 8
  %field.ptr106 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p105, i32 0, i32 9
  %p107 = load ptr, ptr %p, align 8
  %field.addr108 = getelementptr inbounds nuw { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %p107, i32 0, i32 0
  %field.addr109 = getelementptr inbounds nuw { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr %field.addr108, i32 0, i32 2
  store ptr %field.addr109, ptr %field.ptr106, align 8
  ret {} undef
}

define {} @"init__f156__in_s{p:prw_s{}}__out_s{}"({ ptr } %0) {
entry:
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %p, align 8
  ret {} undef
}

declare {} @"deinit__f148__in_s{self:prw_s{_storage:s{allocator:s{},terminal:s{_storage:s{stdin_file:s{stream_address:unative,should_close:bool},stdout_file:s{stream_address:unative,should_close:bool},stderr_file:s{stream_address:unative,should_close:bool},stdin_reader:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative}},stdin_file:prw_s{stream_address:unative,should_close:bool},stdout_file:prw_s{stream_address:unative,should_close:bool},stderr_file:prw_s{stream_address:unative,should_close:bool},stdin_reader:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stdin:prw_abs_Reader,stdout:prw_abs_Writer,stderr:prw_abs_Writer},args:s{count:unative,address:unative},env_vars:s{},file_sys:s{},network:s{},proc_man:s{},clock:s{},rand_gen:s{},ffi:s{}},allocator:prw_s{},terminal:prw_s{_storage:s{stdin_file:s{stream_address:unative,should_close:bool},stdout_file:s{stream_address:unative,should_close:bool},stderr_file:s{stream_address:unative,should_close:bool},stdin_reader:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative}},stdin_file:prw_s{stream_address:unative,should_close:bool},stdout_file:prw_s{stream_address:unative,should_close:bool},stderr_file:prw_s{stream_address:unative,should_close:bool},stdin_reader:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stdin:prw_abs_Reader,stdout:prw_abs_Writer,stderr:prw_abs_Writer},args:prw_s{count:unative,address:unative},env_vars:prw_s{},file_sys:prw_s{},network:prw_s{},proc_man:prw_s{},clock:prw_s{},rand_gen:prw_s{},ffi:prw_s{}},allocator:prw_s{}}__out_s{}"({ ptr, ptr })

declare {} @"deinit__f150__in_s{self:prw_s{_storage:s{stdin_file:s{stream_address:unative,should_close:bool},stdout_file:s{stream_address:unative,should_close:bool},stderr_file:s{stream_address:unative,should_close:bool},stdin_reader:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative}},stdin_file:prw_s{stream_address:unative,should_close:bool},stdout_file:prw_s{stream_address:unative,should_close:bool},stderr_file:prw_s{stream_address:unative,should_close:bool},stdin_reader:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stdin:prw_abs_Reader,stdout:prw_abs_Writer,stderr:prw_abs_Writer},allocator:prw_s{}}__out_s{}"({ ptr, ptr })

define { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"init__f205__in_s{p:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},allocator:prw_s{},base:prw_s{stream_address:unative,should_close:bool},capacity:unative}__out_s{result:choice}"({ ptr, ptr, ptr, i64 } %0) {
entry:
  %payload = alloca { ptr, i64, { ptr, ptr } }, align 8
  %needs.deinit19 = alloca i1, align 1
  %needs.deinit20 = alloca i1, align 1
  %needs.deinit21 = alloca i1, align 1
  %needs.deinit22 = alloca i1, align 1
  %needs.deinit23 = alloca i1, align 1
  %needs.deinit24 = alloca i1, align 1
  %allocated = alloca { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, align 8
  %needs.deinit16 = alloca i1, align 1
  %one = alloca i64, align 8
  %needs.deinit10 = alloca i1, align 1
  %actual_capacity = alloca i64, align 8
  %needs.deinit9 = alloca i1, align 1
  %result = alloca { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, align 8
  %needs.deinit7 = alloca i1, align 1
  %capacity = alloca i64, align 8
  %needs.deinit3 = alloca i1, align 1
  %base = alloca ptr, align 8
  %needs.deinit2 = alloca i1, align 1
  %allocator = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  store i1 false, ptr %needs.deinit2, align 1
  store i1 false, ptr %needs.deinit3, align 1
  %arg = extractvalue { ptr, ptr, ptr, i64 } %0, 0
  store ptr %arg, ptr %p, align 8
  %arg4 = extractvalue { ptr, ptr, ptr, i64 } %0, 1
  store ptr %arg4, ptr %allocator, align 8
  %arg5 = extractvalue { ptr, ptr, ptr, i64 } %0, 2
  store ptr %arg5, ptr %base, align 8
  %arg6 = extractvalue { ptr, ptr, ptr, i64 } %0, 3
  store i64 %arg6, ptr %capacity, align 4
  store i1 false, ptr %needs.deinit7, align 1
  %capacity8 = load i64, ptr %capacity, align 4
  store i1 true, ptr %needs.deinit9, align 1
  store i64 %capacity8, ptr %actual_capacity, align 4
  store i1 true, ptr %needs.deinit10, align 1
  store i64 1, ptr %one, align 4
  %actual_capacity11 = load i64, ptr %actual_capacity, align 4
  %ieq = icmp eq i64 %actual_capacity11, 0
  br i1 %ieq, label %then, label %ifend

then:                                             ; preds = %entry
  %one12 = load i64, ptr %one, align 4
  store i64 %one12, ptr %actual_capacity, align 4
  store i1 true, ptr %needs.deinit9, align 1
  br label %ifend

ifend:                                            ; preds = %then, %entry
  %allocator13 = load ptr, ptr %allocator, align 8
  %actual_capacity14 = load i64, ptr %actual_capacity, align 4
  %lit.insert = insertvalue { ptr, i64 } undef, ptr %allocator13, 0
  %lit.insert15 = insertvalue { ptr, i64 } %lit.insert, i64 %actual_capacity14, 1
  %call = call { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"allocate__f46__in_s{self:prw_s{},size:unative}__out_s{result:choice}"({ ptr, i64 } %lit.insert15)
  %call.unpack = extractvalue { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %call, 0
  store i1 true, ptr %needs.deinit16, align 1
  store { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %call.unpack, ptr %allocated, align 8
  %allocated17 = load { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %allocated, align 8
  store i1 false, ptr %needs.deinit16, align 1
  %match.tag = extractvalue { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %allocated17, 0
  switch i32 %match.tag, label %match.end [
    i32 0, label %match.case.0
    i32 1, label %match.case.1
  ]

match.end:                                        ; preds = %match.case.1, %match.case.0, %ifend
  %1 = load { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %result, align 8
  %2 = insertvalue { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } undef, { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %1, 0
  ret { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %2

match.case.0:                                     ; preds = %ifend
  %allocated18 = load { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %allocated, align 8
  store i1 false, ptr %needs.deinit16, align 1
  %choice.payload = extractvalue { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %allocated18, 1
  store i1 true, ptr %needs.deinit19, align 1
  store i1 true, ptr %needs.deinit20, align 1
  store i1 true, ptr %needs.deinit21, align 1
  store i1 true, ptr %needs.deinit22, align 1
  store i1 true, ptr %needs.deinit23, align 1
  store i1 true, ptr %needs.deinit24, align 1
  store { ptr, i64, { ptr, ptr } } %choice.payload, ptr %payload, align 8
  %p25 = load ptr, ptr %p, align 8
  %base26 = load ptr, ptr %base, align 8
  %payload27 = load { ptr, i64, { ptr, ptr } }, ptr %payload, align 8
  store i1 false, ptr %needs.deinit19, align 1
  store i1 false, ptr %needs.deinit20, align 1
  store i1 false, ptr %needs.deinit21, align 1
  store i1 false, ptr %needs.deinit22, align 1
  store i1 false, ptr %needs.deinit23, align 1
  store i1 false, ptr %needs.deinit24, align 1
  %actual_capacity28 = load i64, ptr %actual_capacity, align 4
  %lit.insert29 = insertvalue { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 } undef, ptr %base26, 0
  %lit.insert30 = insertvalue { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 } %lit.insert29, { ptr, i64, { ptr, ptr } } %payload27, 1
  %lit.insert31 = insertvalue { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 } %lit.insert30, i64 %actual_capacity28, 2
  %lit.insert32 = insertvalue { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 } %lit.insert31, i64 0, 3
  %lit.insert33 = insertvalue { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 } %lit.insert32, i64 0, 4
  store { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 } %lit.insert33, ptr %p25, align 8
  store { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 0, {} undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } undef }, ptr %result, align 8
  store i1 true, ptr %needs.deinit7, align 1
  br label %match.end

match.case.1:                                     ; preds = %ifend
  store { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 1, {} undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } { { i32, i8 } { i32 0, i8 undef }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } { { { ptr, i64, { ptr, ptr } }, i64, i64 } { { ptr, i64, { ptr, ptr } } { ptr null, i64 0, { ptr, ptr } undef }, i64 0, i64 0 } } } }, ptr %result, align 8
  store i1 true, ptr %needs.deinit7, align 1
  br label %match.end
}

define { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"init__f206__in_s{p:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},allocator:prw_s{},base:prw_s{stream_address:unative,should_close:bool},capacity:unative}__out_s{result:choice}"({ ptr, ptr, ptr, i64 } %0) {
entry:
  %payload = alloca { ptr, i64, { ptr, ptr } }, align 8
  %needs.deinit19 = alloca i1, align 1
  %needs.deinit20 = alloca i1, align 1
  %needs.deinit21 = alloca i1, align 1
  %needs.deinit22 = alloca i1, align 1
  %needs.deinit23 = alloca i1, align 1
  %needs.deinit24 = alloca i1, align 1
  %allocated = alloca { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, align 8
  %needs.deinit16 = alloca i1, align 1
  %one = alloca i64, align 8
  %needs.deinit10 = alloca i1, align 1
  %actual_capacity = alloca i64, align 8
  %needs.deinit9 = alloca i1, align 1
  %result = alloca { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, align 8
  %needs.deinit7 = alloca i1, align 1
  %capacity = alloca i64, align 8
  %needs.deinit3 = alloca i1, align 1
  %base = alloca ptr, align 8
  %needs.deinit2 = alloca i1, align 1
  %allocator = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  store i1 false, ptr %needs.deinit2, align 1
  store i1 false, ptr %needs.deinit3, align 1
  %arg = extractvalue { ptr, ptr, ptr, i64 } %0, 0
  store ptr %arg, ptr %p, align 8
  %arg4 = extractvalue { ptr, ptr, ptr, i64 } %0, 1
  store ptr %arg4, ptr %allocator, align 8
  %arg5 = extractvalue { ptr, ptr, ptr, i64 } %0, 2
  store ptr %arg5, ptr %base, align 8
  %arg6 = extractvalue { ptr, ptr, ptr, i64 } %0, 3
  store i64 %arg6, ptr %capacity, align 4
  store i1 false, ptr %needs.deinit7, align 1
  %capacity8 = load i64, ptr %capacity, align 4
  store i1 true, ptr %needs.deinit9, align 1
  store i64 %capacity8, ptr %actual_capacity, align 4
  store i1 true, ptr %needs.deinit10, align 1
  store i64 1, ptr %one, align 4
  %actual_capacity11 = load i64, ptr %actual_capacity, align 4
  %ieq = icmp eq i64 %actual_capacity11, 0
  br i1 %ieq, label %then, label %ifend

then:                                             ; preds = %entry
  %one12 = load i64, ptr %one, align 4
  store i64 %one12, ptr %actual_capacity, align 4
  store i1 true, ptr %needs.deinit9, align 1
  br label %ifend

ifend:                                            ; preds = %then, %entry
  %allocator13 = load ptr, ptr %allocator, align 8
  %actual_capacity14 = load i64, ptr %actual_capacity, align 4
  %lit.insert = insertvalue { ptr, i64 } undef, ptr %allocator13, 0
  %lit.insert15 = insertvalue { ptr, i64 } %lit.insert, i64 %actual_capacity14, 1
  %call = call { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"allocate__f46__in_s{self:prw_s{},size:unative}__out_s{result:choice}"({ ptr, i64 } %lit.insert15)
  %call.unpack = extractvalue { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %call, 0
  store i1 true, ptr %needs.deinit16, align 1
  store { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %call.unpack, ptr %allocated, align 8
  %allocated17 = load { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %allocated, align 8
  store i1 false, ptr %needs.deinit16, align 1
  %match.tag = extractvalue { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %allocated17, 0
  switch i32 %match.tag, label %match.end [
    i32 0, label %match.case.0
    i32 1, label %match.case.1
  ]

match.end:                                        ; preds = %match.case.1, %match.case.0, %ifend
  %1 = load { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %result, align 8
  %2 = insertvalue { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } undef, { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %1, 0
  ret { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %2

match.case.0:                                     ; preds = %ifend
  %allocated18 = load { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %allocated, align 8
  store i1 false, ptr %needs.deinit16, align 1
  %choice.payload = extractvalue { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %allocated18, 1
  store i1 true, ptr %needs.deinit19, align 1
  store i1 true, ptr %needs.deinit20, align 1
  store i1 true, ptr %needs.deinit21, align 1
  store i1 true, ptr %needs.deinit22, align 1
  store i1 true, ptr %needs.deinit23, align 1
  store i1 true, ptr %needs.deinit24, align 1
  store { ptr, i64, { ptr, ptr } } %choice.payload, ptr %payload, align 8
  %p25 = load ptr, ptr %p, align 8
  %base26 = load ptr, ptr %base, align 8
  %payload27 = load { ptr, i64, { ptr, ptr } }, ptr %payload, align 8
  store i1 false, ptr %needs.deinit19, align 1
  store i1 false, ptr %needs.deinit20, align 1
  store i1 false, ptr %needs.deinit21, align 1
  store i1 false, ptr %needs.deinit22, align 1
  store i1 false, ptr %needs.deinit23, align 1
  store i1 false, ptr %needs.deinit24, align 1
  %actual_capacity28 = load i64, ptr %actual_capacity, align 4
  %lit.insert29 = insertvalue { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } undef, ptr %base26, 0
  %lit.insert30 = insertvalue { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } %lit.insert29, { ptr, i64, { ptr, ptr } } %payload27, 1
  %lit.insert31 = insertvalue { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } %lit.insert30, i64 %actual_capacity28, 2
  %lit.insert32 = insertvalue { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } %lit.insert31, i64 0, 3
  store { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } %lit.insert32, ptr %p25, align 8
  store { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 0, {} undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } undef }, ptr %result, align 8
  store i1 true, ptr %needs.deinit7, align 1
  br label %match.end

match.case.1:                                     ; preds = %ifend
  store { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 1, {} undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } { { i32, i8 } { i32 0, i8 undef }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } { { { ptr, i64, { ptr, ptr } }, i64, i64 } { { ptr, i64, { ptr, ptr } } { ptr null, i64 0, { ptr, ptr } undef }, i64 0, i64 0 } } } }, ptr %result, align 8
  store i1 true, ptr %needs.deinit7, align 1
  br label %match.end
}

declare {} @"deinit__f207__in_s{self:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},allocator:prw_s{}}__out_s{}"({ ptr, ptr })

declare {} @"deinit__f208__in_s{self:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},allocator:prw_s{}}__out_s{}"({ ptr, ptr })

declare { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"test_fail_impl__f151__in_s{}__out_s{result:choice}"({})

declare { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"test_skip_impl__f152__in_s{}__out_s{result:choice}"({})

declare { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"fail__f153__in_s{message:pro_char}__out_s{result:choice}"({ ptr })

declare { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"skip__f154__in_s{message:pro_char}__out_s{result:choice}"({ ptr })

declare { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"expect__f155__in_s{condition:bool}__out_s{result:choice}"({ i1 })

define {} @"init__f157__in_s{p:prw_s{allocation_attempts:i32,deallocations:i32,backing_freed_after_elements:bool}}__out_s{}"({ ptr } %0) {
entry:
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %p, align 8
  %p1 = load ptr, ptr %p, align 8
  store { i32, i32, i1 } zeroinitializer, ptr %p1, align 4
  ret {} undef
}

define { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"allocate__f158__in_s{self:prw_s{allocation_attempts:i32,deallocations:i32,backing_freed_after_elements:bool},size:unative}__out_s{result:choice}"({ ptr, i64 } %0) {
entry:
  %allocation = alloca { ptr, i64, { ptr, ptr } }, align 8
  %needs.deinit26 = alloca i1, align 1
  %needs.deinit27 = alloca i1, align 1
  %needs.deinit28 = alloca i1, align 1
  %needs.deinit29 = alloca i1, align 1
  %needs.deinit30 = alloca i1, align 1
  %needs.deinit31 = alloca i1, align 1
  %deallocator = alloca { ptr, ptr }, align 8
  %needs.deinit16 = alloca i1, align 1
  %needs.deinit17 = alloca i1, align 1
  %needs.deinit18 = alloca i1, align 1
  %storage = alloca i64, align 8
  %needs.deinit14 = alloca i1, align 1
  %result = alloca { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, align 8
  %needs.deinit3 = alloca i1, align 1
  %size = alloca i64, align 8
  %needs.deinit1 = alloca i1, align 1
  %self = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  %arg = extractvalue { ptr, i64 } %0, 0
  store ptr %arg, ptr %self, align 8
  %arg2 = extractvalue { ptr, i64 } %0, 1
  store i64 %arg2, ptr %size, align 4
  store i1 false, ptr %needs.deinit3, align 1
  %self4 = load ptr, ptr %self, align 8
  %deref = load { i32, i32, i1 }, ptr %self4, align 4
  %fld = extractvalue { i32, i32, i1 } %deref, 0
  %add = add i32 %fld, 1
  %self5 = load ptr, ptr %self, align 8
  %field.ptr = getelementptr inbounds nuw { i32, i32, i1 }, ptr %self5, i32 0, i32 0
  %self6 = load ptr, ptr %self, align 8
  %deref7 = load { i32, i32, i1 }, ptr %self6, align 4
  %fld8 = extractvalue { i32, i32, i1 } %deref7, 0
  %add9 = add i32 %fld8, 1
  store i32 %add9, ptr %field.ptr, align 4
  %self10 = load ptr, ptr %self, align 8
  %deref11 = load { i32, i32, i1 }, ptr %self10, align 4
  %fld12 = extractvalue { i32, i32, i1 } %deref11, 0
  %ieq = icmp eq i32 %fld12, 4
  br i1 %ieq, label %then, label %ifend

then:                                             ; preds = %entry
  store { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 1, { ptr, i64, { ptr, ptr } } undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } { { i32, i8 } { i32 0, i8 undef }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } { { { ptr, i64, { ptr, ptr } }, i64, i64 } { { ptr, i64, { ptr, ptr } } { ptr null, i64 0, { ptr, ptr } undef }, i64 0, i64 0 } } } }, ptr %result, align 8
  store i1 true, ptr %needs.deinit3, align 1
  %1 = load { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %result, align 8
  %2 = insertvalue { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } undef, { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %1, 0
  ret { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %2

ifend:                                            ; preds = %entry
  %size13 = load i64, ptr %size, align 4
  %lit.insert = insertvalue { i64 } undef, i64 %size13, 0
  %3 = extractvalue { i64 } %lit.insert, 0
  %call = call ptr @malloc(i64 %3)
  %raw.address = ptrtoint ptr %call to i64
  store i1 true, ptr %needs.deinit14, align 1
  store i64 %raw.address, ptr %storage, align 4
  %self15 = load ptr, ptr %self, align 8
  %virtual.data = insertvalue { ptr, ptr } undef, ptr %self15, 0
  %virtual.vtable = insertvalue { ptr, ptr } %virtual.data, ptr @__argi_vtable_3, 1
  store i1 true, ptr %needs.deinit16, align 1
  store i1 true, ptr %needs.deinit17, align 1
  store i1 true, ptr %needs.deinit18, align 1
  store { ptr, ptr } %virtual.vtable, ptr %deallocator, align 8
  %storage19 = load i64, ptr %storage, align 4
  %size20 = load i64, ptr %size, align 4
  %deallocator21 = load { ptr, ptr }, ptr %deallocator, align 8
  %lit.insert22 = insertvalue { i64, i64, { ptr, ptr } } undef, i64 %storage19, 0
  %lit.insert23 = insertvalue { i64, i64, { ptr, ptr } } %lit.insert22, i64 %size20, 1
  %lit.insert24 = insertvalue { i64, i64, { ptr, ptr } } %lit.insert23, { ptr, ptr } %deallocator21, 2
  %call25 = call { { ptr, i64, { ptr, ptr } } } @"establish_allocation__f48__in_s{storage:unative,size:unative,deallocator:s{data:prw_any,vtable:pro_any}}__out_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}}}"({ i64, i64, { ptr, ptr } } %lit.insert24)
  %call.unpack = extractvalue { { ptr, i64, { ptr, ptr } } } %call25, 0
  store i1 true, ptr %needs.deinit26, align 1
  store i1 true, ptr %needs.deinit27, align 1
  store i1 true, ptr %needs.deinit28, align 1
  store i1 true, ptr %needs.deinit29, align 1
  store i1 true, ptr %needs.deinit30, align 1
  store i1 true, ptr %needs.deinit31, align 1
  store { ptr, i64, { ptr, ptr } } %call.unpack, ptr %allocation, align 8
  %allocation32 = load { ptr, i64, { ptr, ptr } }, ptr %allocation, align 8
  store i1 false, ptr %needs.deinit26, align 1
  store i1 false, ptr %needs.deinit27, align 1
  store i1 false, ptr %needs.deinit28, align 1
  store i1 false, ptr %needs.deinit29, align 1
  store i1 false, ptr %needs.deinit30, align 1
  store i1 false, ptr %needs.deinit31, align 1
  %choice.payload = insertvalue { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 0, { ptr, i64, { ptr, ptr } } undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } undef }, { ptr, i64, { ptr, ptr } } %allocation32, 1
  store { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %choice.payload, ptr %result, align 8
  store i1 true, ptr %needs.deinit3, align 1
  %4 = load { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %result, align 8
  %5 = insertvalue { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } undef, { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %4, 0
  ret { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %5
}

define {} @"deallocate__f159__in_s{self:prw_s{allocation_attempts:i32,deallocations:i32,backing_freed_after_elements:bool},data:prw_u8,size:unative}__out_s{}"({ ptr, ptr, i64 } %0) {
entry:
  %address = alloca i64, align 8
  %needs.deinit27 = alloca i1, align 1
  %three = alloca i64, align 8
  %needs.deinit5 = alloca i1, align 1
  %size = alloca i64, align 8
  %needs.deinit2 = alloca i1, align 1
  %data = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %self = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  store i1 false, ptr %needs.deinit2, align 1
  %arg = extractvalue { ptr, ptr, i64 } %0, 0
  store ptr %arg, ptr %self, align 8
  %arg3 = extractvalue { ptr, ptr, i64 } %0, 1
  store ptr %arg3, ptr %data, align 8
  %arg4 = extractvalue { ptr, ptr, i64 } %0, 2
  store i64 %arg4, ptr %size, align 4
  store i1 true, ptr %needs.deinit5, align 1
  store i64 3, ptr %three, align 4
  %size6 = load i64, ptr %size, align 4
  %three7 = load i64, ptr %three, align 4
  %mul = mul i64 %three7, 40
  %ieq = icmp eq i64 %size6, %mul
  br i1 %ieq, label %then, label %ifend

then:                                             ; preds = %entry
  %self8 = load ptr, ptr %self, align 8
  %deref = load { i32, i32, i1 }, ptr %self8, align 4
  %fld = extractvalue { i32, i32, i1 } %deref, 1
  %ieq9 = icmp eq i32 %fld, 2
  %self10 = load ptr, ptr %self, align 8
  %field.ptr = getelementptr inbounds nuw { i32, i32, i1 }, ptr %self10, i32 0, i32 2
  %self11 = load ptr, ptr %self, align 8
  %deref12 = load { i32, i32, i1 }, ptr %self11, align 4
  %fld13 = extractvalue { i32, i32, i1 } %deref12, 1
  %ieq14 = icmp eq i32 %fld13, 2
  store i1 %ieq14, ptr %field.ptr, align 1
  br label %ifend

ifend:                                            ; preds = %then, %entry
  %self15 = load ptr, ptr %self, align 8
  %deref16 = load { i32, i32, i1 }, ptr %self15, align 4
  %fld17 = extractvalue { i32, i32, i1 } %deref16, 1
  %add = add i32 %fld17, 1
  %self18 = load ptr, ptr %self, align 8
  %field.ptr19 = getelementptr inbounds nuw { i32, i32, i1 }, ptr %self18, i32 0, i32 1
  %self20 = load ptr, ptr %self, align 8
  %deref21 = load { i32, i32, i1 }, ptr %self20, align 4
  %fld22 = extractvalue { i32, i32, i1 } %deref21, 1
  %add23 = add i32 %fld22, 1
  store i32 %add23, ptr %field.ptr19, align 4
  %data24 = load ptr, ptr %data, align 8
  %ptr.to.int = ptrtoint ptr %data24 to i64
  %data25 = load ptr, ptr %data, align 8
  %ptr.to.int26 = ptrtoint ptr %data25 to i64
  store i1 true, ptr %needs.deinit27, align 1
  store i64 %ptr.to.int26, ptr %address, align 4
  %address28 = load i64, ptr %address, align 4
  %lit.insert = insertvalue { i64 } undef, i64 %address28, 0
  %1 = extractvalue { i64 } %lit.insert, 0
  %free.address = inttoptr i64 %1 to ptr
  call void @free(ptr %free.address)
  ret {} undef
}

define { i32 } @"main__f160__in_s{system:s{_storage:s{allocator:s{},terminal:s{_storage:s{stdin_file:s{stream_address:unative,should_close:bool},stdout_file:s{stream_address:unative,should_close:bool},stderr_file:s{stream_address:unative,should_close:bool},stdin_reader:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative}},stdin_file:prw_s{stream_address:unative,should_close:bool},stdout_file:prw_s{stream_address:unative,should_close:bool},stderr_file:prw_s{stream_address:unative,should_close:bool},stdin_reader:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stdin:prw_abs_Reader,stdout:prw_abs_Writer,stderr:prw_abs_Writer},args:s{count:unative,address:unative},env_vars:s{},file_sys:s{},network:s{},proc_man:s{},clock:s{},rand_gen:s{},ffi:s{}},allocator:prw_s{},terminal:prw_s{_storage:s{stdin_file:s{stream_address:unative,should_close:bool},stdout_file:s{stream_address:unative,should_close:bool},stderr_file:s{stream_address:unative,should_close:bool},stdin_reader:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative}},stdin_file:prw_s{stream_address:unative,should_close:bool},stdout_file:prw_s{stream_address:unative,should_close:bool},stderr_file:prw_s{stream_address:unative,should_close:bool},stdin_reader:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stdin:prw_abs_Reader,stdout:prw_abs_Writer,stderr:prw_abs_Writer},args:prw_s{count:unative,address:unative},env_vars:prw_s{},file_sys:prw_s{},network:prw_s{},proc_man:prw_s{},clock:prw_s{},rand_gen:prw_s{},ffi:prw_s{}}}__out_s{status_code:i32}"({ { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr } } %0) {
entry:
  %copied = alloca { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, align 8
  %needs.deinit171 = alloca i1, align 1
  %failing = alloca { i32, i32, i1 }, align 8
  %needs.deinit164 = alloca i1, align 1
  %needs.deinit165 = alloca i1, align 1
  %needs.deinit166 = alloca i1, align 1
  %needs.deinit167 = alloca i1, align 1
  %third = alloca { { ptr, i64, { ptr, ptr } }, i64 }, align 8
  %needs.deinit140 = alloca i1, align 1
  %needs.deinit141 = alloca i1, align 1
  %needs.deinit142 = alloca i1, align 1
  %needs.deinit143 = alloca i1, align 1
  %needs.deinit144 = alloca i1, align 1
  %needs.deinit145 = alloca i1, align 1
  %needs.deinit146 = alloca i1, align 1
  %needs.deinit147 = alloca i1, align 1
  %second = alloca { { ptr, i64, { ptr, ptr } }, i64 }, align 8
  %needs.deinit120 = alloca i1, align 1
  %needs.deinit121 = alloca i1, align 1
  %needs.deinit122 = alloca i1, align 1
  %needs.deinit123 = alloca i1, align 1
  %needs.deinit124 = alloca i1, align 1
  %needs.deinit125 = alloca i1, align 1
  %needs.deinit126 = alloca i1, align 1
  %needs.deinit127 = alloca i1, align 1
  %first = alloca { { ptr, i64, { ptr, ptr } }, i64 }, align 8
  %needs.deinit100 = alloca i1, align 1
  %needs.deinit101 = alloca i1, align 1
  %needs.deinit102 = alloca i1, align 1
  %needs.deinit103 = alloca i1, align 1
  %needs.deinit104 = alloca i1, align 1
  %needs.deinit105 = alloca i1, align 1
  %needs.deinit106 = alloca i1, align 1
  %needs.deinit107 = alloca i1, align 1
  %source = alloca { { ptr, i64, { ptr, ptr } }, i64, i64 }, align 8
  %needs.deinit79 = alloca i1, align 1
  %needs.deinit80 = alloca i1, align 1
  %needs.deinit81 = alloca i1, align 1
  %needs.deinit82 = alloca i1, align 1
  %needs.deinit83 = alloca i1, align 1
  %needs.deinit84 = alloca i1, align 1
  %needs.deinit85 = alloca i1, align 1
  %needs.deinit86 = alloca i1, align 1
  %needs.deinit87 = alloca i1, align 1
  %status_code = alloca i32, align 4
  %needs.deinit74 = alloca i1, align 1
  %system = alloca { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, align 8
  %needs.deinit = alloca i1, align 1
  %needs.deinit1 = alloca i1, align 1
  %needs.deinit2 = alloca i1, align 1
  %needs.deinit3 = alloca i1, align 1
  %needs.deinit4 = alloca i1, align 1
  %needs.deinit5 = alloca i1, align 1
  %needs.deinit6 = alloca i1, align 1
  %needs.deinit7 = alloca i1, align 1
  %needs.deinit8 = alloca i1, align 1
  %needs.deinit9 = alloca i1, align 1
  %needs.deinit10 = alloca i1, align 1
  %needs.deinit11 = alloca i1, align 1
  %needs.deinit12 = alloca i1, align 1
  %needs.deinit13 = alloca i1, align 1
  %needs.deinit14 = alloca i1, align 1
  %needs.deinit15 = alloca i1, align 1
  %needs.deinit16 = alloca i1, align 1
  %needs.deinit17 = alloca i1, align 1
  %needs.deinit18 = alloca i1, align 1
  %needs.deinit19 = alloca i1, align 1
  %needs.deinit20 = alloca i1, align 1
  %needs.deinit21 = alloca i1, align 1
  %needs.deinit22 = alloca i1, align 1
  %needs.deinit23 = alloca i1, align 1
  %needs.deinit24 = alloca i1, align 1
  %needs.deinit25 = alloca i1, align 1
  %needs.deinit26 = alloca i1, align 1
  %needs.deinit27 = alloca i1, align 1
  %needs.deinit28 = alloca i1, align 1
  %needs.deinit29 = alloca i1, align 1
  %needs.deinit30 = alloca i1, align 1
  %needs.deinit31 = alloca i1, align 1
  %needs.deinit32 = alloca i1, align 1
  %needs.deinit33 = alloca i1, align 1
  %needs.deinit34 = alloca i1, align 1
  %needs.deinit35 = alloca i1, align 1
  %needs.deinit36 = alloca i1, align 1
  %needs.deinit37 = alloca i1, align 1
  %needs.deinit38 = alloca i1, align 1
  %needs.deinit39 = alloca i1, align 1
  %needs.deinit40 = alloca i1, align 1
  %needs.deinit41 = alloca i1, align 1
  %needs.deinit42 = alloca i1, align 1
  %needs.deinit43 = alloca i1, align 1
  %needs.deinit44 = alloca i1, align 1
  %needs.deinit45 = alloca i1, align 1
  %needs.deinit46 = alloca i1, align 1
  %needs.deinit47 = alloca i1, align 1
  %needs.deinit48 = alloca i1, align 1
  %needs.deinit49 = alloca i1, align 1
  %needs.deinit50 = alloca i1, align 1
  %needs.deinit51 = alloca i1, align 1
  %needs.deinit52 = alloca i1, align 1
  %needs.deinit53 = alloca i1, align 1
  %needs.deinit54 = alloca i1, align 1
  %needs.deinit55 = alloca i1, align 1
  %needs.deinit56 = alloca i1, align 1
  %needs.deinit57 = alloca i1, align 1
  %needs.deinit58 = alloca i1, align 1
  %needs.deinit59 = alloca i1, align 1
  %needs.deinit60 = alloca i1, align 1
  %needs.deinit61 = alloca i1, align 1
  %needs.deinit62 = alloca i1, align 1
  %needs.deinit63 = alloca i1, align 1
  %needs.deinit64 = alloca i1, align 1
  %needs.deinit65 = alloca i1, align 1
  %needs.deinit66 = alloca i1, align 1
  %needs.deinit67 = alloca i1, align 1
  %needs.deinit68 = alloca i1, align 1
  %needs.deinit69 = alloca i1, align 1
  %needs.deinit70 = alloca i1, align 1
  %needs.deinit71 = alloca i1, align 1
  %needs.deinit72 = alloca i1, align 1
  %needs.deinit73 = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  store i1 false, ptr %needs.deinit2, align 1
  store i1 false, ptr %needs.deinit3, align 1
  store i1 false, ptr %needs.deinit4, align 1
  store i1 false, ptr %needs.deinit5, align 1
  store i1 false, ptr %needs.deinit6, align 1
  store i1 false, ptr %needs.deinit7, align 1
  store i1 false, ptr %needs.deinit8, align 1
  store i1 false, ptr %needs.deinit9, align 1
  store i1 false, ptr %needs.deinit10, align 1
  store i1 false, ptr %needs.deinit11, align 1
  store i1 false, ptr %needs.deinit12, align 1
  store i1 false, ptr %needs.deinit13, align 1
  store i1 false, ptr %needs.deinit14, align 1
  store i1 false, ptr %needs.deinit15, align 1
  store i1 false, ptr %needs.deinit16, align 1
  store i1 false, ptr %needs.deinit17, align 1
  store i1 false, ptr %needs.deinit18, align 1
  store i1 false, ptr %needs.deinit19, align 1
  store i1 false, ptr %needs.deinit20, align 1
  store i1 false, ptr %needs.deinit21, align 1
  store i1 false, ptr %needs.deinit22, align 1
  store i1 false, ptr %needs.deinit23, align 1
  store i1 false, ptr %needs.deinit24, align 1
  store i1 false, ptr %needs.deinit25, align 1
  store i1 false, ptr %needs.deinit26, align 1
  store i1 false, ptr %needs.deinit27, align 1
  store i1 false, ptr %needs.deinit28, align 1
  store i1 false, ptr %needs.deinit29, align 1
  store i1 false, ptr %needs.deinit30, align 1
  store i1 false, ptr %needs.deinit31, align 1
  store i1 false, ptr %needs.deinit32, align 1
  store i1 false, ptr %needs.deinit33, align 1
  store i1 false, ptr %needs.deinit34, align 1
  store i1 false, ptr %needs.deinit35, align 1
  store i1 false, ptr %needs.deinit36, align 1
  store i1 false, ptr %needs.deinit37, align 1
  store i1 false, ptr %needs.deinit38, align 1
  store i1 false, ptr %needs.deinit39, align 1
  store i1 false, ptr %needs.deinit40, align 1
  store i1 false, ptr %needs.deinit41, align 1
  store i1 false, ptr %needs.deinit42, align 1
  store i1 false, ptr %needs.deinit43, align 1
  store i1 false, ptr %needs.deinit44, align 1
  store i1 false, ptr %needs.deinit45, align 1
  store i1 false, ptr %needs.deinit46, align 1
  store i1 false, ptr %needs.deinit47, align 1
  store i1 false, ptr %needs.deinit48, align 1
  store i1 false, ptr %needs.deinit49, align 1
  store i1 false, ptr %needs.deinit50, align 1
  store i1 false, ptr %needs.deinit51, align 1
  store i1 false, ptr %needs.deinit52, align 1
  store i1 false, ptr %needs.deinit53, align 1
  store i1 false, ptr %needs.deinit54, align 1
  store i1 false, ptr %needs.deinit55, align 1
  store i1 false, ptr %needs.deinit56, align 1
  store i1 false, ptr %needs.deinit57, align 1
  store i1 false, ptr %needs.deinit58, align 1
  store i1 false, ptr %needs.deinit59, align 1
  store i1 false, ptr %needs.deinit60, align 1
  store i1 false, ptr %needs.deinit61, align 1
  store i1 false, ptr %needs.deinit62, align 1
  store i1 false, ptr %needs.deinit63, align 1
  store i1 false, ptr %needs.deinit64, align 1
  store i1 false, ptr %needs.deinit65, align 1
  store i1 false, ptr %needs.deinit66, align 1
  store i1 false, ptr %needs.deinit67, align 1
  store i1 false, ptr %needs.deinit68, align 1
  store i1 false, ptr %needs.deinit69, align 1
  store i1 false, ptr %needs.deinit70, align 1
  store i1 false, ptr %needs.deinit71, align 1
  store i1 false, ptr %needs.deinit72, align 1
  store i1 false, ptr %needs.deinit73, align 1
  %arg = extractvalue { { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr } } %0, 0
  store { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr } %arg, ptr %system, align 8
  store i1 true, ptr %needs.deinit74, align 1
  store i32 0, ptr %status_code, align 4
  %type.init.tmp = alloca { { ptr, i64, { ptr, ptr } }, i64, i64 }, align 8
  %system75 = load { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %system, align 8
  %fld = extractvalue { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr } %system75, 1
  %lit.insert = insertvalue { ptr, i64 } undef, ptr %fld, 0
  %lit.insert76 = insertvalue { ptr, i64 } %lit.insert, i64 3, 1
  %ctor.arg.p = insertvalue { ptr, ptr, i64 } undef, ptr %type.init.tmp, 0
  %ctor.arg.extract = extractvalue { ptr, i64 } %lit.insert76, 0
  %ctor.arg.insert = insertvalue { ptr, ptr, i64 } %ctor.arg.p, ptr %ctor.arg.extract, 1
  %ctor.arg.extract77 = extractvalue { ptr, i64 } %lit.insert76, 1
  %ctor.arg.insert78 = insertvalue { ptr, ptr, i64 } %ctor.arg.insert, i64 %ctor.arg.extract77, 2
  %call = call { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"init__f210__in_s{p:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},allocator:prw_s{},capacity:unative}__out_s{result:choice}"({ ptr, ptr, i64 } %ctor.arg.insert78)
  %type.init.result = load { { ptr, i64, { ptr, ptr } }, i64, i64 }, ptr %type.init.tmp, align 8
  store i1 true, ptr %needs.deinit79, align 1
  store i1 true, ptr %needs.deinit80, align 1
  store i1 true, ptr %needs.deinit81, align 1
  store i1 true, ptr %needs.deinit82, align 1
  store i1 true, ptr %needs.deinit83, align 1
  store i1 true, ptr %needs.deinit84, align 1
  store i1 true, ptr %needs.deinit85, align 1
  store i1 true, ptr %needs.deinit86, align 1
  store i1 true, ptr %needs.deinit87, align 1
  store { { ptr, i64, { ptr, ptr } }, i64, i64 } %type.init.result, ptr %source, align 8
  %type.init.tmp88 = alloca { { ptr, i64, { ptr, ptr } }, i64 }, align 8
  %system89 = load { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %system, align 8
  %fld90 = extractvalue { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr } %system89, 1
  %lit.insert91 = insertvalue { ptr, i64 } undef, ptr %fld90, 0
  %lit.insert92 = insertvalue { ptr, i64 } %lit.insert91, i64 1, 1
  %ctor.arg.p93 = insertvalue { ptr, ptr, i64 } undef, ptr %type.init.tmp88, 0
  %ctor.arg.extract94 = extractvalue { ptr, i64 } %lit.insert92, 0
  %ctor.arg.insert95 = insertvalue { ptr, ptr, i64 } %ctor.arg.p93, ptr %ctor.arg.extract94, 1
  %ctor.arg.extract96 = extractvalue { ptr, i64 } %lit.insert92, 1
  %ctor.arg.insert97 = insertvalue { ptr, ptr, i64 } %ctor.arg.insert95, i64 %ctor.arg.extract96, 2
  %call98 = call { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"init__f216__in_s{p:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},allocator:prw_s{},length:unative}__out_s{result:choice}"({ ptr, ptr, i64 } %ctor.arg.insert97)
  %type.init.result99 = load { { ptr, i64, { ptr, ptr } }, i64 }, ptr %type.init.tmp88, align 8
  store i1 true, ptr %needs.deinit100, align 1
  store i1 true, ptr %needs.deinit101, align 1
  store i1 true, ptr %needs.deinit102, align 1
  store i1 true, ptr %needs.deinit103, align 1
  store i1 true, ptr %needs.deinit104, align 1
  store i1 true, ptr %needs.deinit105, align 1
  store i1 true, ptr %needs.deinit106, align 1
  store i1 true, ptr %needs.deinit107, align 1
  store { { ptr, i64, { ptr, ptr } }, i64 } %type.init.result99, ptr %first, align 8
  %type.init.tmp108 = alloca { { ptr, i64, { ptr, ptr } }, i64 }, align 8
  %system109 = load { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %system, align 8
  %fld110 = extractvalue { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr } %system109, 1
  %lit.insert111 = insertvalue { ptr, i64 } undef, ptr %fld110, 0
  %lit.insert112 = insertvalue { ptr, i64 } %lit.insert111, i64 1, 1
  %ctor.arg.p113 = insertvalue { ptr, ptr, i64 } undef, ptr %type.init.tmp108, 0
  %ctor.arg.extract114 = extractvalue { ptr, i64 } %lit.insert112, 0
  %ctor.arg.insert115 = insertvalue { ptr, ptr, i64 } %ctor.arg.p113, ptr %ctor.arg.extract114, 1
  %ctor.arg.extract116 = extractvalue { ptr, i64 } %lit.insert112, 1
  %ctor.arg.insert117 = insertvalue { ptr, ptr, i64 } %ctor.arg.insert115, i64 %ctor.arg.extract116, 2
  %call118 = call { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"init__f216__in_s{p:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},allocator:prw_s{},length:unative}__out_s{result:choice}"({ ptr, ptr, i64 } %ctor.arg.insert117)
  %type.init.result119 = load { { ptr, i64, { ptr, ptr } }, i64 }, ptr %type.init.tmp108, align 8
  store i1 true, ptr %needs.deinit120, align 1
  store i1 true, ptr %needs.deinit121, align 1
  store i1 true, ptr %needs.deinit122, align 1
  store i1 true, ptr %needs.deinit123, align 1
  store i1 true, ptr %needs.deinit124, align 1
  store i1 true, ptr %needs.deinit125, align 1
  store i1 true, ptr %needs.deinit126, align 1
  store i1 true, ptr %needs.deinit127, align 1
  store { { ptr, i64, { ptr, ptr } }, i64 } %type.init.result119, ptr %second, align 8
  %type.init.tmp128 = alloca { { ptr, i64, { ptr, ptr } }, i64 }, align 8
  %system129 = load { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %system, align 8
  %fld130 = extractvalue { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr } %system129, 1
  %lit.insert131 = insertvalue { ptr, i64 } undef, ptr %fld130, 0
  %lit.insert132 = insertvalue { ptr, i64 } %lit.insert131, i64 1, 1
  %ctor.arg.p133 = insertvalue { ptr, ptr, i64 } undef, ptr %type.init.tmp128, 0
  %ctor.arg.extract134 = extractvalue { ptr, i64 } %lit.insert132, 0
  %ctor.arg.insert135 = insertvalue { ptr, ptr, i64 } %ctor.arg.p133, ptr %ctor.arg.extract134, 1
  %ctor.arg.extract136 = extractvalue { ptr, i64 } %lit.insert132, 1
  %ctor.arg.insert137 = insertvalue { ptr, ptr, i64 } %ctor.arg.insert135, i64 %ctor.arg.extract136, 2
  %call138 = call { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"init__f216__in_s{p:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},allocator:prw_s{},length:unative}__out_s{result:choice}"({ ptr, ptr, i64 } %ctor.arg.insert137)
  %type.init.result139 = load { { ptr, i64, { ptr, ptr } }, i64 }, ptr %type.init.tmp128, align 8
  store i1 true, ptr %needs.deinit140, align 1
  store i1 true, ptr %needs.deinit141, align 1
  store i1 true, ptr %needs.deinit142, align 1
  store i1 true, ptr %needs.deinit143, align 1
  store i1 true, ptr %needs.deinit144, align 1
  store i1 true, ptr %needs.deinit145, align 1
  store i1 true, ptr %needs.deinit146, align 1
  store i1 true, ptr %needs.deinit147, align 1
  store { { ptr, i64, { ptr, ptr } }, i64 } %type.init.result139, ptr %third, align 8
  %first148 = load { { ptr, i64, { ptr, ptr } }, i64 }, ptr %first, align 8
  store i1 false, ptr %needs.deinit100, align 1
  store i1 false, ptr %needs.deinit101, align 1
  store i1 false, ptr %needs.deinit102, align 1
  store i1 false, ptr %needs.deinit103, align 1
  store i1 false, ptr %needs.deinit104, align 1
  store i1 false, ptr %needs.deinit105, align 1
  store i1 false, ptr %needs.deinit106, align 1
  store i1 false, ptr %needs.deinit107, align 1
  %lit.insert149 = insertvalue { ptr, { { ptr, i64, { ptr, ptr } }, i64 } } undef, ptr %source, 0
  %lit.insert150 = insertvalue { ptr, { { ptr, i64, { ptr, ptr } }, i64 } } %lit.insert149, { { ptr, i64, { ptr, ptr } }, i64 } %first148, 1
  %call151 = call {} @"push_assume_capacity__f217__in_s{self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},value:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{}"({ ptr, { { ptr, i64, { ptr, ptr } }, i64 } } %lit.insert150)
  %second152 = load { { ptr, i64, { ptr, ptr } }, i64 }, ptr %second, align 8
  store i1 false, ptr %needs.deinit120, align 1
  store i1 false, ptr %needs.deinit121, align 1
  store i1 false, ptr %needs.deinit122, align 1
  store i1 false, ptr %needs.deinit123, align 1
  store i1 false, ptr %needs.deinit124, align 1
  store i1 false, ptr %needs.deinit125, align 1
  store i1 false, ptr %needs.deinit126, align 1
  store i1 false, ptr %needs.deinit127, align 1
  %lit.insert153 = insertvalue { ptr, { { ptr, i64, { ptr, ptr } }, i64 } } undef, ptr %source, 0
  %lit.insert154 = insertvalue { ptr, { { ptr, i64, { ptr, ptr } }, i64 } } %lit.insert153, { { ptr, i64, { ptr, ptr } }, i64 } %second152, 1
  %call155 = call {} @"push_assume_capacity__f217__in_s{self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},value:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{}"({ ptr, { { ptr, i64, { ptr, ptr } }, i64 } } %lit.insert154)
  %third156 = load { { ptr, i64, { ptr, ptr } }, i64 }, ptr %third, align 8
  store i1 false, ptr %needs.deinit140, align 1
  store i1 false, ptr %needs.deinit141, align 1
  store i1 false, ptr %needs.deinit142, align 1
  store i1 false, ptr %needs.deinit143, align 1
  store i1 false, ptr %needs.deinit144, align 1
  store i1 false, ptr %needs.deinit145, align 1
  store i1 false, ptr %needs.deinit146, align 1
  store i1 false, ptr %needs.deinit147, align 1
  %lit.insert157 = insertvalue { ptr, { { ptr, i64, { ptr, ptr } }, i64 } } undef, ptr %source, 0
  %lit.insert158 = insertvalue { ptr, { { ptr, i64, { ptr, ptr } }, i64 } } %lit.insert157, { { ptr, i64, { ptr, ptr } }, i64 } %third156, 1
  %call159 = call {} @"push_assume_capacity__f217__in_s{self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},value:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{}"({ ptr, { { ptr, i64, { ptr, ptr } }, i64 } } %lit.insert158)
  %type.init.tmp160 = alloca { i32, i32, i1 }, align 8
  %ctor.arg.p161 = insertvalue { ptr } undef, ptr %type.init.tmp160, 0
  %call162 = call {} @"init__f157__in_s{p:prw_s{allocation_attempts:i32,deallocations:i32,backing_freed_after_elements:bool}}__out_s{}"({ ptr } %ctor.arg.p161)
  %type.init.result163 = load { i32, i32, i1 }, ptr %type.init.tmp160, align 4
  store i1 true, ptr %needs.deinit164, align 1
  store i1 true, ptr %needs.deinit165, align 1
  store i1 true, ptr %needs.deinit166, align 1
  store i1 true, ptr %needs.deinit167, align 1
  store { i32, i32, i1 } %type.init.result163, ptr %failing, align 4
  %lit.insert168 = insertvalue { ptr, ptr } undef, ptr %source, 0
  %lit.insert169 = insertvalue { ptr, ptr } %lit.insert168, ptr %failing, 1
  %call170 = call { { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"copy__f219__in_s{self:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},allocator:prw_s{allocation_attempts:i32,deallocations:i32,backing_freed_after_elements:bool}}__out_s{result:choice}"({ ptr, ptr } %lit.insert169)
  %call.unpack = extractvalue { { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %call170, 0
  store i1 true, ptr %needs.deinit171, align 1
  store { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %call.unpack, ptr %copied, align 8
  %copied172 = load { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %copied, align 8
  %choice.lhs.tag = extractvalue { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %copied172, 0
  %choice.eq = icmp eq i32 %choice.lhs.tag, 0
  br i1 %choice.eq, label %then, label %ifend

then:                                             ; preds = %entry
  store i32 1, ptr %status_code, align 4
  store i1 true, ptr %needs.deinit74, align 1
  %system173 = load { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %system, align 8
  %fld174 = extractvalue { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr } %system173, 1
  %lit.insert175 = insertvalue { ptr, ptr } undef, ptr %fld174, 0
  %lit.insert176 = insertvalue { ptr, ptr } %lit.insert175, ptr %source, 1
  %call177 = call {} @"deinit__f211__in_s{allocator:prw_s{},self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative}}__out_s{}"({ ptr, ptr } %lit.insert176)
  store i1 false, ptr %needs.deinit79, align 1
  store i1 false, ptr %needs.deinit80, align 1
  store i1 false, ptr %needs.deinit81, align 1
  store i1 false, ptr %needs.deinit82, align 1
  store i1 false, ptr %needs.deinit83, align 1
  store i1 false, ptr %needs.deinit84, align 1
  store i1 false, ptr %needs.deinit85, align 1
  store i1 false, ptr %needs.deinit86, align 1
  store i1 false, ptr %needs.deinit87, align 1
  %needs.deinit178 = load i1, ptr %needs.deinit79, align 1
  br i1 %needs.deinit178, label %autodeinit.run, label %autodeinit.done

ifend:                                            ; preds = %entry
  %failing180 = load { i32, i32, i1 }, ptr %failing, align 4
  %fld181 = extractvalue { i32, i32, i1 } %failing180, 0
  %ine = icmp ne i32 %fld181, 4
  br i1 %ine, label %logic.or.merge, label %logic.or.rhs

autodeinit.run:                                   ; preds = %then
  store i1 false, ptr %needs.deinit79, align 1
  %autodeinit.override.field = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %system, i32 0, i32 1
  %autodeinit.field = load ptr, ptr %autodeinit.override.field, align 8
  %autodeinit.arg = insertvalue { ptr, ptr } undef, ptr %autodeinit.field, 0
  %autodeinit.arg179 = insertvalue { ptr, ptr } %autodeinit.arg, ptr %source, 1
  %1 = call {} @"deinit__f211__in_s{allocator:prw_s{},self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative}}__out_s{}"({ ptr, ptr } %autodeinit.arg179)
  br label %autodeinit.done

autodeinit.done:                                  ; preds = %autodeinit.run, %then
  %2 = load i32, ptr %status_code, align 4
  %3 = insertvalue { i32 } undef, i32 %2, 0
  ret { i32 } %3

logic.or.rhs:                                     ; preds = %ifend
  %failing182 = load { i32, i32, i1 }, ptr %failing, align 4
  %fld183 = extractvalue { i32, i32, i1 } %failing182, 1
  %ine184 = icmp ne i32 %fld183, 3
  br label %logic.or.merge

logic.or.merge:                                   ; preds = %logic.or.rhs, %ifend
  %logic.or = phi i1 [ true, %ifend ], [ %ine184, %logic.or.rhs ]
  br i1 %logic.or, label %then185, label %ifend186

then185:                                          ; preds = %logic.or.merge
  store i32 2, ptr %status_code, align 4
  store i1 true, ptr %needs.deinit74, align 1
  %system187 = load { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %system, align 8
  %fld188 = extractvalue { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr } %system187, 1
  %lit.insert189 = insertvalue { ptr, ptr } undef, ptr %fld188, 0
  %lit.insert190 = insertvalue { ptr, ptr } %lit.insert189, ptr %source, 1
  %call191 = call {} @"deinit__f211__in_s{allocator:prw_s{},self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative}}__out_s{}"({ ptr, ptr } %lit.insert190)
  store i1 false, ptr %needs.deinit79, align 1
  store i1 false, ptr %needs.deinit80, align 1
  store i1 false, ptr %needs.deinit81, align 1
  store i1 false, ptr %needs.deinit82, align 1
  store i1 false, ptr %needs.deinit83, align 1
  store i1 false, ptr %needs.deinit84, align 1
  store i1 false, ptr %needs.deinit85, align 1
  store i1 false, ptr %needs.deinit86, align 1
  store i1 false, ptr %needs.deinit87, align 1
  %needs.deinit194 = load i1, ptr %needs.deinit79, align 1
  br i1 %needs.deinit194, label %autodeinit.run192, label %autodeinit.done193

ifend186:                                         ; preds = %logic.or.merge
  %failing199 = load { i32, i32, i1 }, ptr %failing, align 4
  %fld200 = extractvalue { i32, i32, i1 } %failing199, 2
  %ieq = icmp eq i1 %fld200, false
  br i1 %ieq, label %then201, label %ifend202

autodeinit.run192:                                ; preds = %then185
  store i1 false, ptr %needs.deinit79, align 1
  %autodeinit.override.field195 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %system, i32 0, i32 1
  %autodeinit.field196 = load ptr, ptr %autodeinit.override.field195, align 8
  %autodeinit.arg197 = insertvalue { ptr, ptr } undef, ptr %autodeinit.field196, 0
  %autodeinit.arg198 = insertvalue { ptr, ptr } %autodeinit.arg197, ptr %source, 1
  %4 = call {} @"deinit__f211__in_s{allocator:prw_s{},self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative}}__out_s{}"({ ptr, ptr } %autodeinit.arg198)
  br label %autodeinit.done193

autodeinit.done193:                               ; preds = %autodeinit.run192, %then185
  %5 = load i32, ptr %status_code, align 4
  %6 = insertvalue { i32 } undef, i32 %5, 0
  ret { i32 } %6

then201:                                          ; preds = %ifend186
  store i32 3, ptr %status_code, align 4
  store i1 true, ptr %needs.deinit74, align 1
  br label %ifend202

ifend202:                                         ; preds = %then201, %ifend186
  %system203 = load { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %system, align 8
  %fld204 = extractvalue { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr } %system203, 1
  %lit.insert205 = insertvalue { ptr, ptr } undef, ptr %fld204, 0
  %lit.insert206 = insertvalue { ptr, ptr } %lit.insert205, ptr %source, 1
  %call207 = call {} @"deinit__f211__in_s{allocator:prw_s{},self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative}}__out_s{}"({ ptr, ptr } %lit.insert206)
  store i1 false, ptr %needs.deinit79, align 1
  store i1 false, ptr %needs.deinit80, align 1
  store i1 false, ptr %needs.deinit81, align 1
  store i1 false, ptr %needs.deinit82, align 1
  store i1 false, ptr %needs.deinit83, align 1
  store i1 false, ptr %needs.deinit84, align 1
  store i1 false, ptr %needs.deinit85, align 1
  store i1 false, ptr %needs.deinit86, align 1
  store i1 false, ptr %needs.deinit87, align 1
  %needs.deinit210 = load i1, ptr %needs.deinit79, align 1
  br i1 %needs.deinit210, label %autodeinit.run208, label %autodeinit.done209

autodeinit.run208:                                ; preds = %ifend202
  store i1 false, ptr %needs.deinit79, align 1
  %autodeinit.override.field211 = getelementptr inbounds nuw { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %system, i32 0, i32 1
  %autodeinit.field212 = load ptr, ptr %autodeinit.override.field211, align 8
  %autodeinit.arg213 = insertvalue { ptr, ptr } undef, ptr %autodeinit.field212, 0
  %autodeinit.arg214 = insertvalue { ptr, ptr } %autodeinit.arg213, ptr %source, 1
  %7 = call {} @"deinit__f211__in_s{allocator:prw_s{},self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative}}__out_s{}"({ ptr, ptr } %autodeinit.arg214)
  br label %autodeinit.done209

autodeinit.done209:                               ; preds = %autodeinit.run208, %ifend202
  %8 = load i32, ptr %status_code, align 4
  %9 = insertvalue { i32 } undef, i32 %8, 0
  ret { i32 } %9
}

define { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"init__f210__in_s{p:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},allocator:prw_s{},capacity:unative}__out_s{result:choice}"({ ptr, ptr, i64 } %0) {
entry:
  %payload = alloca { ptr, i64, { ptr, ptr } }, align 8
  %needs.deinit22 = alloca i1, align 1
  %needs.deinit23 = alloca i1, align 1
  %needs.deinit24 = alloca i1, align 1
  %needs.deinit25 = alloca i1, align 1
  %needs.deinit26 = alloca i1, align 1
  %needs.deinit27 = alloca i1, align 1
  %allocated = alloca { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, align 8
  %needs.deinit19 = alloca i1, align 1
  %bytes = alloca i64, align 8
  %needs.deinit15 = alloca i1, align 1
  %actual_capacity = alloca i64, align 8
  %needs.deinit8 = alloca i1, align 1
  %element_size = alloca i64, align 8
  %needs.deinit6 = alloca i1, align 1
  %result = alloca { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, align 8
  %needs.deinit5 = alloca i1, align 1
  %capacity = alloca i64, align 8
  %needs.deinit2 = alloca i1, align 1
  %allocator = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  store i1 false, ptr %needs.deinit2, align 1
  %arg = extractvalue { ptr, ptr, i64 } %0, 0
  store ptr %arg, ptr %p, align 8
  %arg3 = extractvalue { ptr, ptr, i64 } %0, 1
  store ptr %arg3, ptr %allocator, align 8
  %arg4 = extractvalue { ptr, ptr, i64 } %0, 2
  store i64 %arg4, ptr %capacity, align 4
  store i1 false, ptr %needs.deinit5, align 1
  store i1 true, ptr %needs.deinit6, align 1
  store i64 40, ptr %element_size, align 4
  %capacity7 = load i64, ptr %capacity, align 4
  store i1 true, ptr %needs.deinit8, align 1
  store i64 %capacity7, ptr %actual_capacity, align 4
  %actual_capacity9 = load i64, ptr %actual_capacity, align 4
  %ieq = icmp eq i64 %actual_capacity9, 0
  br i1 %ieq, label %then, label %ifend

then:                                             ; preds = %entry
  store i64 1, ptr %actual_capacity, align 4
  store i1 true, ptr %needs.deinit8, align 1
  br label %ifend

ifend:                                            ; preds = %then, %entry
  %actual_capacity10 = load i64, ptr %actual_capacity, align 4
  %element_size11 = load i64, ptr %element_size, align 4
  %mul = mul i64 %actual_capacity10, %element_size11
  %actual_capacity12 = load i64, ptr %actual_capacity, align 4
  %element_size13 = load i64, ptr %element_size, align 4
  %mul14 = mul i64 %actual_capacity12, %element_size13
  store i1 true, ptr %needs.deinit15, align 1
  store i64 %mul14, ptr %bytes, align 4
  %allocator16 = load ptr, ptr %allocator, align 8
  %bytes17 = load i64, ptr %bytes, align 4
  %lit.insert = insertvalue { ptr, i64 } undef, ptr %allocator16, 0
  %lit.insert18 = insertvalue { ptr, i64 } %lit.insert, i64 %bytes17, 1
  %call = call { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"allocate__f46__in_s{self:prw_s{},size:unative}__out_s{result:choice}"({ ptr, i64 } %lit.insert18)
  %call.unpack = extractvalue { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %call, 0
  store i1 true, ptr %needs.deinit19, align 1
  store { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %call.unpack, ptr %allocated, align 8
  %allocated20 = load { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %allocated, align 8
  store i1 false, ptr %needs.deinit19, align 1
  %match.tag = extractvalue { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %allocated20, 0
  switch i32 %match.tag, label %match.end [
    i32 0, label %match.case.0
    i32 1, label %match.case.1
  ]

match.end:                                        ; preds = %match.case.1, %match.case.0, %ifend
  %1 = load { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %result, align 8
  %2 = insertvalue { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } undef, { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %1, 0
  ret { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %2

match.case.0:                                     ; preds = %ifend
  %allocated21 = load { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %allocated, align 8
  store i1 false, ptr %needs.deinit19, align 1
  %choice.payload = extractvalue { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %allocated21, 1
  store i1 true, ptr %needs.deinit22, align 1
  store i1 true, ptr %needs.deinit23, align 1
  store i1 true, ptr %needs.deinit24, align 1
  store i1 true, ptr %needs.deinit25, align 1
  store i1 true, ptr %needs.deinit26, align 1
  store i1 true, ptr %needs.deinit27, align 1
  store { ptr, i64, { ptr, ptr } } %choice.payload, ptr %payload, align 8
  %p28 = load ptr, ptr %p, align 8
  %payload29 = load { ptr, i64, { ptr, ptr } }, ptr %payload, align 8
  store i1 false, ptr %needs.deinit22, align 1
  store i1 false, ptr %needs.deinit23, align 1
  store i1 false, ptr %needs.deinit24, align 1
  store i1 false, ptr %needs.deinit25, align 1
  store i1 false, ptr %needs.deinit26, align 1
  store i1 false, ptr %needs.deinit27, align 1
  %actual_capacity30 = load i64, ptr %actual_capacity, align 4
  %lit.insert31 = insertvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } undef, { ptr, i64, { ptr, ptr } } %payload29, 0
  %lit.insert32 = insertvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %lit.insert31, i64 0, 1
  %lit.insert33 = insertvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %lit.insert32, i64 %actual_capacity30, 2
  store { { ptr, i64, { ptr, ptr } }, i64, i64 } %lit.insert33, ptr %p28, align 8
  store { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 0, {} undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } undef }, ptr %result, align 8
  store i1 true, ptr %needs.deinit5, align 1
  br label %match.end

match.case.1:                                     ; preds = %ifend
  store { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 1, {} undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } { { i32, i8 } { i32 0, i8 undef }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } { { { ptr, i64, { ptr, ptr } }, i64, i64 } { { ptr, i64, { ptr, ptr } } { ptr null, i64 0, { ptr, ptr } undef }, i64 0, i64 0 } } } }, ptr %result, align 8
  store i1 true, ptr %needs.deinit5, align 1
  br label %match.end
}

define { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"init__f216__in_s{p:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},allocator:prw_s{},length:unative}__out_s{result:choice}"({ ptr, ptr, i64 } %0) {
entry:
  %payload = alloca { ptr, i64, { ptr, ptr } }, align 8
  %needs.deinit16 = alloca i1, align 1
  %needs.deinit17 = alloca i1, align 1
  %needs.deinit18 = alloca i1, align 1
  %needs.deinit19 = alloca i1, align 1
  %needs.deinit20 = alloca i1, align 1
  %needs.deinit21 = alloca i1, align 1
  %allocated = alloca { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, align 8
  %needs.deinit13 = alloca i1, align 1
  %allocation_size = alloca i64, align 8
  %needs.deinit9 = alloca i1, align 1
  %result = alloca { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, align 8
  %needs.deinit5 = alloca i1, align 1
  %length = alloca i64, align 8
  %needs.deinit2 = alloca i1, align 1
  %allocator = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  store i1 false, ptr %needs.deinit2, align 1
  %arg = extractvalue { ptr, ptr, i64 } %0, 0
  store ptr %arg, ptr %p, align 8
  %arg3 = extractvalue { ptr, ptr, i64 } %0, 1
  store ptr %arg3, ptr %allocator, align 8
  %arg4 = extractvalue { ptr, ptr, i64 } %0, 2
  store i64 %arg4, ptr %length, align 4
  store i1 false, ptr %needs.deinit5, align 1
  %length6 = load i64, ptr %length, align 4
  %add = add i64 %length6, 1
  %length7 = load i64, ptr %length, align 4
  %add8 = add i64 %length7, 1
  store i1 true, ptr %needs.deinit9, align 1
  store i64 %add8, ptr %allocation_size, align 4
  %allocator10 = load ptr, ptr %allocator, align 8
  %allocation_size11 = load i64, ptr %allocation_size, align 4
  %lit.insert = insertvalue { ptr, i64 } undef, ptr %allocator10, 0
  %lit.insert12 = insertvalue { ptr, i64 } %lit.insert, i64 %allocation_size11, 1
  %call = call { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"allocate__f46__in_s{self:prw_s{},size:unative}__out_s{result:choice}"({ ptr, i64 } %lit.insert12)
  %call.unpack = extractvalue { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %call, 0
  store i1 true, ptr %needs.deinit13, align 1
  store { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %call.unpack, ptr %allocated, align 8
  %allocated14 = load { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %allocated, align 8
  store i1 false, ptr %needs.deinit13, align 1
  %match.tag = extractvalue { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %allocated14, 0
  switch i32 %match.tag, label %match.end [
    i32 0, label %match.case.0
    i32 1, label %match.case.1
  ]

match.end:                                        ; preds = %match.case.1, %match.case.0, %entry
  %1 = load { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %result, align 8
  %2 = insertvalue { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } undef, { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %1, 0
  ret { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %2

match.case.0:                                     ; preds = %entry
  %allocated15 = load { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %allocated, align 8
  store i1 false, ptr %needs.deinit13, align 1
  %choice.payload = extractvalue { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %allocated15, 1
  store i1 true, ptr %needs.deinit16, align 1
  store i1 true, ptr %needs.deinit17, align 1
  store i1 true, ptr %needs.deinit18, align 1
  store i1 true, ptr %needs.deinit19, align 1
  store i1 true, ptr %needs.deinit20, align 1
  store i1 true, ptr %needs.deinit21, align 1
  store { ptr, i64, { ptr, ptr } } %choice.payload, ptr %payload, align 8
  %p22 = load ptr, ptr %p, align 8
  %payload23 = load { ptr, i64, { ptr, ptr } }, ptr %payload, align 8
  store i1 false, ptr %needs.deinit16, align 1
  store i1 false, ptr %needs.deinit17, align 1
  store i1 false, ptr %needs.deinit18, align 1
  store i1 false, ptr %needs.deinit19, align 1
  store i1 false, ptr %needs.deinit20, align 1
  store i1 false, ptr %needs.deinit21, align 1
  %length24 = load i64, ptr %length, align 4
  %lit.insert25 = insertvalue { { ptr, i64, { ptr, ptr } }, i64 } undef, { ptr, i64, { ptr, ptr } } %payload23, 0
  %lit.insert26 = insertvalue { { ptr, i64, { ptr, ptr } }, i64 } %lit.insert25, i64 %length24, 1
  store { { ptr, i64, { ptr, ptr } }, i64 } %lit.insert26, ptr %p22, align 8
  %p27 = load ptr, ptr %p, align 8
  %length28 = load i64, ptr %length, align 4
  %lit.insert29 = insertvalue { ptr, i64, i8 } undef, ptr %p27, 0
  %lit.insert30 = insertvalue { ptr, i64, i8 } %lit.insert29, i64 %length28, 1
  %lit.insert31 = insertvalue { ptr, i64, i8 } %lit.insert30, i8 0, 2
  %call32 = call {} @"bytes_set__f72__in_s{string:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},index:unative,value:u8}__out_s{}"({ ptr, i64, i8 } %lit.insert31)
  store { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 0, {} undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } undef }, ptr %result, align 8
  store i1 true, ptr %needs.deinit5, align 1
  br label %match.end

match.case.1:                                     ; preds = %entry
  store { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 1, {} undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } { { i32, i8 } { i32 0, i8 undef }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } { { { ptr, i64, { ptr, ptr } }, i64, i64 } { { ptr, i64, { ptr, ptr } } { ptr null, i64 0, { ptr, ptr } undef }, i64 0, i64 0 } } } }, ptr %result, align 8
  store i1 true, ptr %needs.deinit5, align 1
  br label %match.end
}

define {} @"push_assume_capacity__f217__in_s{self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},value:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{}"({ ptr, { { ptr, i64, { ptr, ptr } }, i64 } } %0) {
entry:
  %ptr = alloca ptr, align 8
  %needs.deinit15 = alloca i1, align 1
  %offset = alloca i64, align 8
  %needs.deinit11 = alloca i1, align 1
  %value = alloca { { ptr, i64, { ptr, ptr } }, i64 }, align 8
  %needs.deinit1 = alloca i1, align 1
  %needs.deinit2 = alloca i1, align 1
  %needs.deinit3 = alloca i1, align 1
  %needs.deinit4 = alloca i1, align 1
  %needs.deinit5 = alloca i1, align 1
  %needs.deinit6 = alloca i1, align 1
  %needs.deinit7 = alloca i1, align 1
  %needs.deinit8 = alloca i1, align 1
  %self = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  store i1 false, ptr %needs.deinit2, align 1
  store i1 false, ptr %needs.deinit3, align 1
  store i1 false, ptr %needs.deinit4, align 1
  store i1 false, ptr %needs.deinit5, align 1
  store i1 false, ptr %needs.deinit6, align 1
  store i1 false, ptr %needs.deinit7, align 1
  store i1 false, ptr %needs.deinit8, align 1
  %arg = extractvalue { ptr, { { ptr, i64, { ptr, ptr } }, i64 } } %0, 0
  store ptr %arg, ptr %self, align 8
  %arg9 = extractvalue { ptr, { { ptr, i64, { ptr, ptr } }, i64 } } %0, 1
  store { { ptr, i64, { ptr, ptr } }, i64 } %arg9, ptr %value, align 8
  %self10 = load ptr, ptr %self, align 8
  %deref = load { { ptr, i64, { ptr, ptr } }, i64, i64 }, ptr %self10, align 8
  %fld = extractvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %deref, 1
  store i1 true, ptr %needs.deinit11, align 1
  store i64 %fld, ptr %offset, align 4
  %self12 = load ptr, ptr %self, align 8
  %offset13 = load i64, ptr %offset, align 4
  %lit.insert = insertvalue { ptr, i64 } undef, ptr %self12, 0
  %lit.insert14 = insertvalue { ptr, i64 } %lit.insert, i64 %offset13, 1
  %call = call { ptr } @"dynamic_array_element_rw_pointer__f212__in_s{array:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},offset:unative}__out_s{pointer:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}"({ ptr, i64 } %lit.insert14)
  %call.unpack = extractvalue { ptr } %call, 0
  store i1 true, ptr %needs.deinit15, align 1
  store ptr %call.unpack, ptr %ptr, align 8
  %ptr16 = load ptr, ptr %ptr, align 8
  %value17 = load { { ptr, i64, { ptr, ptr } }, i64 }, ptr %value, align 8
  store i1 false, ptr %needs.deinit1, align 1
  store i1 false, ptr %needs.deinit2, align 1
  store i1 false, ptr %needs.deinit3, align 1
  store i1 false, ptr %needs.deinit4, align 1
  store i1 false, ptr %needs.deinit5, align 1
  store i1 false, ptr %needs.deinit6, align 1
  store i1 false, ptr %needs.deinit7, align 1
  store i1 false, ptr %needs.deinit8, align 1
  store { { ptr, i64, { ptr, ptr } }, i64 } %value17, ptr %ptr16, align 8
  %offset18 = load i64, ptr %offset, align 4
  %add = add i64 %offset18, 1
  %self19 = load ptr, ptr %self, align 8
  %field.ptr = getelementptr inbounds nuw { { ptr, i64, { ptr, ptr } }, i64, i64 }, ptr %self19, i32 0, i32 1
  %offset20 = load i64, ptr %offset, align 4
  %add21 = add i64 %offset20, 1
  store i64 %add21, ptr %field.ptr, align 4
  ret {} undef
}

define { { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"copy__f219__in_s{self:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},allocator:prw_s{allocation_attempts:i32,deallocations:i32,backing_freed_after_elements:bool}}__out_s{result:choice}"({ ptr, ptr } %0) {
entry:
  %element = alloca { { ptr, i64, { ptr, ptr } }, i64 }, align 8
  %needs.deinit87 = alloca i1, align 1
  %needs.deinit88 = alloca i1, align 1
  %needs.deinit89 = alloca i1, align 1
  %needs.deinit90 = alloca i1, align 1
  %needs.deinit91 = alloca i1, align 1
  %needs.deinit92 = alloca i1, align 1
  %needs.deinit93 = alloca i1, align 1
  %needs.deinit94 = alloca i1, align 1
  %ptr = alloca ptr, align 8
  %needs.deinit30 = alloca i1, align 1
  %i = alloca i64, align 8
  %needs.deinit19 = alloca i1, align 1
  %initialized = alloca { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, align 8
  %needs.deinit17 = alloca i1, align 1
  %out = alloca { { ptr, i64, { ptr, ptr } }, i64, i64 }, align 8
  %needs.deinit4 = alloca i1, align 1
  %needs.deinit5 = alloca i1, align 1
  %needs.deinit6 = alloca i1, align 1
  %needs.deinit7 = alloca i1, align 1
  %needs.deinit8 = alloca i1, align 1
  %needs.deinit9 = alloca i1, align 1
  %needs.deinit10 = alloca i1, align 1
  %needs.deinit11 = alloca i1, align 1
  %needs.deinit12 = alloca i1, align 1
  %result = alloca { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, align 8
  %needs.deinit3 = alloca i1, align 1
  %allocator = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %self = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  %arg = extractvalue { ptr, ptr } %0, 0
  store ptr %arg, ptr %self, align 8
  %arg2 = extractvalue { ptr, ptr } %0, 1
  store ptr %arg2, ptr %allocator, align 8
  store i1 false, ptr %needs.deinit3, align 1
  store i1 false, ptr %needs.deinit4, align 1
  store i1 false, ptr %needs.deinit5, align 1
  store i1 false, ptr %needs.deinit6, align 1
  store i1 false, ptr %needs.deinit7, align 1
  store i1 false, ptr %needs.deinit8, align 1
  store i1 false, ptr %needs.deinit9, align 1
  store i1 false, ptr %needs.deinit10, align 1
  store i1 false, ptr %needs.deinit11, align 1
  store i1 false, ptr %needs.deinit12, align 1
  %allocator13 = load ptr, ptr %allocator, align 8
  %self14 = load ptr, ptr %self, align 8
  %deref = load { { ptr, i64, { ptr, ptr } }, i64, i64 }, ptr %self14, align 8
  %fld = extractvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %deref, 1
  %lit.insert = insertvalue { ptr, ptr, i64 } undef, ptr %out, 0
  %lit.insert15 = insertvalue { ptr, ptr, i64 } %lit.insert, ptr %allocator13, 1
  %lit.insert16 = insertvalue { ptr, ptr, i64 } %lit.insert15, i64 %fld, 2
  %call = call { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"init__f223__in_s{p:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},allocator:prw_s{allocation_attempts:i32,deallocations:i32,backing_freed_after_elements:bool},capacity:unative}__out_s{result:choice}"({ ptr, ptr, i64 } %lit.insert16)
  %call.unpack = extractvalue { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %call, 0
  store i1 true, ptr %needs.deinit17, align 1
  store { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %call.unpack, ptr %initialized, align 8
  %initialized18 = load { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %initialized, align 8
  %choice.lhs.tag = extractvalue { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %initialized18, 0
  %choice.eq = icmp eq i32 %choice.lhs.tag, 1
  br i1 %choice.eq, label %then, label %ifend

then:                                             ; preds = %entry
  store { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 1, { { ptr, i64, { ptr, ptr } }, i64, i64 } undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } { { i32, i8 } { i32 0, i8 undef }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } { { { ptr, i64, { ptr, ptr } }, i64, i64 } { { ptr, i64, { ptr, ptr } } { ptr null, i64 0, { ptr, ptr } undef }, i64 0, i64 0 } } } }, ptr %result, align 8
  store i1 true, ptr %needs.deinit3, align 1
  %1 = load { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %result, align 8
  %2 = insertvalue { { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } undef, { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %1, 0
  ret { { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %2

ifend:                                            ; preds = %entry
  store i1 true, ptr %needs.deinit19, align 1
  store i64 0, ptr %i, align 4
  br label %while.cond

while.cond:                                       ; preds = %errable.ok48, %ifend
  %i20 = load i64, ptr %i, align 4
  %self21 = load ptr, ptr %self, align 8
  %deref22 = load { { ptr, i64, { ptr, ptr } }, i64, i64 }, ptr %self21, align 8
  %fld23 = extractvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %deref22, 1
  %ilt = icmp ult i64 %i20, %fld23
  br i1 %ilt, label %while.body, label %while.end

while.body:                                       ; preds = %while.cond
  %self24 = load ptr, ptr %self, align 8
  %i25 = load i64, ptr %i, align 4
  %lit.insert26 = insertvalue { ptr, i64 } undef, ptr %self24, 0
  %lit.insert27 = insertvalue { ptr, i64 } %lit.insert26, i64 %i25, 1
  %call28 = call { ptr } @"dynamic_array_element_ro_pointer__f224__in_s{array:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},offset:unative}__out_s{pointer:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}"({ ptr, i64 } %lit.insert27)
  %call.unpack29 = extractvalue { ptr } %call28, 0
  store i1 true, ptr %needs.deinit30, align 1
  store ptr %call.unpack29, ptr %ptr, align 8
  %ptr31 = load ptr, ptr %ptr, align 8
  %allocator32 = load ptr, ptr %allocator, align 8
  %lit.insert33 = insertvalue { ptr, ptr } undef, ptr %ptr31, 0
  %lit.insert34 = insertvalue { ptr, ptr } %lit.insert33, ptr %allocator32, 1
  %call35 = call { { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"copy__f227__in_s{self:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},allocator:prw_s{allocation_attempts:i32,deallocations:i32,backing_freed_after_elements:bool}}__out_s{result:choice}"({ ptr, ptr } %lit.insert34)
  %call.unpack36 = extractvalue { { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %call35, 0
  %errable.tag = extractvalue { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %call.unpack36, 0
  %errable.is_error = icmp eq i32 %errable.tag, 1
  br i1 %errable.is_error, label %errable.error, label %errable.ok

while.end:                                        ; preds = %while.cond
  %out102 = load { { ptr, i64, { ptr, ptr } }, i64, i64 }, ptr %out, align 8
  store i1 false, ptr %needs.deinit4, align 1
  store i1 false, ptr %needs.deinit5, align 1
  store i1 false, ptr %needs.deinit6, align 1
  store i1 false, ptr %needs.deinit7, align 1
  store i1 false, ptr %needs.deinit8, align 1
  store i1 false, ptr %needs.deinit9, align 1
  store i1 false, ptr %needs.deinit10, align 1
  store i1 false, ptr %needs.deinit11, align 1
  store i1 false, ptr %needs.deinit12, align 1
  %choice.payload = insertvalue { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 0, { { ptr, i64, { ptr, ptr } }, i64, i64 } undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } undef }, { { ptr, i64, { ptr, ptr } }, i64, i64 } %out102, 1
  store { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %choice.payload, ptr %result, align 8
  store i1 true, ptr %needs.deinit3, align 1
  %3 = load { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %result, align 8
  %4 = insertvalue { { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } undef, { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %3, 0
  ret { { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %4

errable.error:                                    ; preds = %while.body
  %errable.error.payload = extractvalue { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %call.unpack36, 2
  %error.reason = extractvalue { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } %errable.error.payload, 0
  %error.trace = extractvalue { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } %errable.error.payload, 1
  %error.trace.entries = extractvalue { { { ptr, i64, { ptr, ptr } }, i64, i64 } } %error.trace, 0
  %trace.entries.allocation = extractvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %error.trace.entries, 0
  %trace.entries.data = extractvalue { ptr, i64, { ptr, ptr } } %trace.entries.allocation, 0
  %trace.entries.length = extractvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %error.trace.entries, 1
  %trace.entries.capacity = extractvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %error.trace.entries, 2
  %trace.is_full = icmp eq i64 %trace.entries.length, %trace.entries.capacity
  br i1 %trace.is_full, label %trace.grow, label %trace.reuse

errable.ok:                                       ; preds = %while.body
  %errable.ok.payload = extractvalue { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %call.unpack36, 1
  %ptr39 = load ptr, ptr %ptr, align 8
  %allocator40 = load ptr, ptr %allocator, align 8
  %lit.insert41 = insertvalue { ptr, ptr } undef, ptr %ptr39, 0
  %lit.insert42 = insertvalue { ptr, ptr } %lit.insert41, ptr %allocator40, 1
  %call43 = call { { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"copy__f227__in_s{self:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},allocator:prw_s{allocation_attempts:i32,deallocations:i32,backing_freed_after_elements:bool}}__out_s{result:choice}"({ ptr, ptr } %lit.insert42)
  %call.unpack44 = extractvalue { { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %call43, 0
  %errable.tag45 = extractvalue { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %call.unpack44, 0
  %errable.is_error46 = icmp eq i32 %errable.tag45, 1
  br i1 %errable.is_error46, label %errable.error47, label %errable.ok48

trace.grow:                                       ; preds = %errable.error
  %trace.capacity.zero = icmp eq i64 %trace.entries.capacity, 0
  %trace.capacity.doubled = mul i64 %trace.entries.capacity, 2
  %trace.capacity = select i1 %trace.capacity.zero, i64 1, i64 %trace.capacity.doubled
  %trace.bytes = mul i64 %trace.capacity, 40
  %malloc.call = call ptr @malloc(i64 %trace.bytes)
  %trace.copy_bytes = mul i64 %trace.entries.length, 40
  call void @memcpy(ptr %malloc.call, ptr %trace.entries.data, i64 %trace.copy_bytes)
  call void @free(ptr %trace.entries.data)
  %trace.alloc.data = insertvalue { ptr, i64, { ptr, ptr } } undef, ptr %malloc.call, 0
  %trace.alloc.size = insertvalue { ptr, i64, { ptr, ptr } } %trace.alloc.data, i64 %trace.bytes, 1
  %trace.entries.alloc = insertvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } undef, { ptr, i64, { ptr, ptr } } %trace.alloc.size, 0
  %trace.entries.length37 = insertvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %trace.entries.alloc, i64 %trace.entries.length, 1
  %trace.entries.capacity38 = insertvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %trace.entries.length37, i64 %trace.capacity, 2
  br label %trace.merge

trace.reuse:                                      ; preds = %errable.error
  br label %trace.merge

trace.merge:                                      ; preds = %trace.reuse, %trace.grow
  %trace.entries.current = phi { { ptr, i64, { ptr, ptr } }, i64, i64 } [ %trace.entries.capacity38, %trace.grow ], [ %error.trace.entries, %trace.reuse ]
  %trace.alloc.current = extractvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %trace.entries.current, 0
  %trace.data.current = extractvalue { ptr, i64, { ptr, ptr } } %trace.alloc.current, 0
  %trace.data.addr = ptrtoint ptr %trace.data.current to i64
  %trace.offset = mul i64 %trace.entries.length, 40
  %trace.entry.addr = add i64 %trace.data.addr, %trace.offset
  %trace.entry.ptr = inttoptr i64 %trace.entry.addr to ptr
  store { i64, i64, ptr, ptr, ptr } { i64 115, i64 38, ptr null, ptr @trace_source_line.14, ptr @trace_source_file.13 }, ptr %trace.entry.ptr, align 8
  %trace.length.next = add i64 %trace.entries.length, 1
  %trace.entries.final_length = insertvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %trace.entries.current, i64 %trace.length.next, 1
  %trace.final.entries = insertvalue { { { ptr, i64, { ptr, ptr } }, i64, i64 } } undef, { { ptr, i64, { ptr, ptr } }, i64, i64 } %trace.entries.final_length, 0
  %error.final.reason = insertvalue { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } undef, { i32, i8 } %error.reason, 0
  %error.final.trace = insertvalue { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } %error.final.reason, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } %trace.final.entries, 1
  %errable.error.updated = insertvalue { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 1, { { ptr, i64, { ptr, ptr } }, i64, i64 } undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } undef }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } %error.final.trace, 2
  %errable.return = insertvalue { { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } undef, { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %errable.error.updated, 0
  ret { { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %errable.return

errable.error47:                                  ; preds = %errable.ok
  %errable.error.payload49 = extractvalue { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %call.unpack44, 2
  %error.reason50 = extractvalue { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } %errable.error.payload49, 0
  %error.trace51 = extractvalue { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } %errable.error.payload49, 1
  %error.trace.entries52 = extractvalue { { { ptr, i64, { ptr, ptr } }, i64, i64 } } %error.trace51, 0
  %trace.entries.allocation53 = extractvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %error.trace.entries52, 0
  %trace.entries.data54 = extractvalue { ptr, i64, { ptr, ptr } } %trace.entries.allocation53, 0
  %trace.entries.length55 = extractvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %error.trace.entries52, 1
  %trace.entries.capacity56 = extractvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %error.trace.entries52, 2
  %trace.is_full57 = icmp eq i64 %trace.entries.length55, %trace.entries.capacity56
  br i1 %trace.is_full57, label %trace.grow58, label %trace.reuse59

errable.ok48:                                     ; preds = %errable.ok
  %errable.ok.payload86 = extractvalue { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %call.unpack44, 1
  store i1 true, ptr %needs.deinit87, align 1
  store i1 true, ptr %needs.deinit88, align 1
  store i1 true, ptr %needs.deinit89, align 1
  store i1 true, ptr %needs.deinit90, align 1
  store i1 true, ptr %needs.deinit91, align 1
  store i1 true, ptr %needs.deinit92, align 1
  store i1 true, ptr %needs.deinit93, align 1
  store i1 true, ptr %needs.deinit94, align 1
  store { { ptr, i64, { ptr, ptr } }, i64 } %errable.ok.payload86, ptr %element, align 8
  %element95 = load { { ptr, i64, { ptr, ptr } }, i64 }, ptr %element, align 8
  store i1 false, ptr %needs.deinit87, align 1
  store i1 false, ptr %needs.deinit88, align 1
  store i1 false, ptr %needs.deinit89, align 1
  store i1 false, ptr %needs.deinit90, align 1
  store i1 false, ptr %needs.deinit91, align 1
  store i1 false, ptr %needs.deinit92, align 1
  store i1 false, ptr %needs.deinit93, align 1
  store i1 false, ptr %needs.deinit94, align 1
  %lit.insert96 = insertvalue { ptr, { { ptr, i64, { ptr, ptr } }, i64 } } undef, ptr %out, 0
  %lit.insert97 = insertvalue { ptr, { { ptr, i64, { ptr, ptr } }, i64 } } %lit.insert96, { { ptr, i64, { ptr, ptr } }, i64 } %element95, 1
  %call98 = call {} @"push_assume_capacity__f217__in_s{self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},value:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{}"({ ptr, { { ptr, i64, { ptr, ptr } }, i64 } } %lit.insert97)
  %i99 = load i64, ptr %i, align 4
  %add = add i64 %i99, 1
  %i100 = load i64, ptr %i, align 4
  %add101 = add i64 %i100, 1
  store i64 %add101, ptr %i, align 4
  store i1 true, ptr %needs.deinit19, align 1
  br label %while.cond

trace.grow58:                                     ; preds = %errable.error47
  %trace.capacity.zero61 = icmp eq i64 %trace.entries.capacity56, 0
  %trace.capacity.doubled62 = mul i64 %trace.entries.capacity56, 2
  %trace.capacity63 = select i1 %trace.capacity.zero61, i64 1, i64 %trace.capacity.doubled62
  %trace.bytes64 = mul i64 %trace.capacity63, 40
  %malloc.call65 = call ptr @malloc(i64 %trace.bytes64)
  %trace.copy_bytes66 = mul i64 %trace.entries.length55, 40
  call void @memcpy(ptr %malloc.call65, ptr %trace.entries.data54, i64 %trace.copy_bytes66)
  call void @free(ptr %trace.entries.data54)
  %trace.alloc.data67 = insertvalue { ptr, i64, { ptr, ptr } } undef, ptr %malloc.call65, 0
  %trace.alloc.size68 = insertvalue { ptr, i64, { ptr, ptr } } %trace.alloc.data67, i64 %trace.bytes64, 1
  %trace.entries.alloc69 = insertvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } undef, { ptr, i64, { ptr, ptr } } %trace.alloc.size68, 0
  %trace.entries.length70 = insertvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %trace.entries.alloc69, i64 %trace.entries.length55, 1
  %trace.entries.capacity71 = insertvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %trace.entries.length70, i64 %trace.capacity63, 2
  br label %trace.merge60

trace.reuse59:                                    ; preds = %errable.error47
  br label %trace.merge60

trace.merge60:                                    ; preds = %trace.reuse59, %trace.grow58
  %trace.entries.current72 = phi { { ptr, i64, { ptr, ptr } }, i64, i64 } [ %trace.entries.capacity71, %trace.grow58 ], [ %error.trace.entries52, %trace.reuse59 ]
  %trace.alloc.current73 = extractvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %trace.entries.current72, 0
  %trace.data.current74 = extractvalue { ptr, i64, { ptr, ptr } } %trace.alloc.current73, 0
  %trace.data.addr75 = ptrtoint ptr %trace.data.current74 to i64
  %trace.offset76 = mul i64 %trace.entries.length55, 40
  %trace.entry.addr77 = add i64 %trace.data.addr75, %trace.offset76
  %trace.entry.ptr78 = inttoptr i64 %trace.entry.addr77 to ptr
  store { i64, i64, ptr, ptr, ptr } { i64 115, i64 38, ptr null, ptr @trace_source_line.16, ptr @trace_source_file.15 }, ptr %trace.entry.ptr78, align 8
  %trace.length.next79 = add i64 %trace.entries.length55, 1
  %trace.entries.final_length80 = insertvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %trace.entries.current72, i64 %trace.length.next79, 1
  %trace.final.entries81 = insertvalue { { { ptr, i64, { ptr, ptr } }, i64, i64 } } undef, { { ptr, i64, { ptr, ptr } }, i64, i64 } %trace.entries.final_length80, 0
  %error.final.reason82 = insertvalue { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } undef, { i32, i8 } %error.reason50, 0
  %error.final.trace83 = insertvalue { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } %error.final.reason82, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } %trace.final.entries81, 1
  %errable.error.updated84 = insertvalue { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 1, { { ptr, i64, { ptr, ptr } }, i64, i64 } undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } undef }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } %error.final.trace83, 2
  %errable.return85 = insertvalue { { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } undef, { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %errable.error.updated84, 0
  ret { { i32, { { ptr, i64, { ptr, ptr } }, i64, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %errable.return85
}

define {} @"deinit__f211__in_s{allocator:prw_s{},self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative}}__out_s{}"({ ptr, ptr } %0) {
entry:
  %slot = alloca ptr, align 8
  %needs.deinit9 = alloca i1, align 1
  %i = alloca i64, align 8
  %needs.deinit3 = alloca i1, align 1
  %self = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %allocator = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  %arg = extractvalue { ptr, ptr } %0, 0
  store ptr %arg, ptr %allocator, align 8
  %arg2 = extractvalue { ptr, ptr } %0, 1
  store ptr %arg2, ptr %self, align 8
  store i1 true, ptr %needs.deinit3, align 1
  store i64 0, ptr %i, align 4
  br label %while.cond

while.cond:                                       ; preds = %while.body, %entry
  %i4 = load i64, ptr %i, align 4
  %self5 = load ptr, ptr %self, align 8
  %deref = load { { ptr, i64, { ptr, ptr } }, i64, i64 }, ptr %self5, align 8
  %fld = extractvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %deref, 1
  %ilt = icmp ult i64 %i4, %fld
  br i1 %ilt, label %while.body, label %while.end

while.body:                                       ; preds = %while.cond
  %self6 = load ptr, ptr %self, align 8
  %i7 = load i64, ptr %i, align 4
  %lit.insert = insertvalue { ptr, i64 } undef, ptr %self6, 0
  %lit.insert8 = insertvalue { ptr, i64 } %lit.insert, i64 %i7, 1
  %call = call { ptr } @"dynamic_array_element_rw_pointer__f212__in_s{array:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},offset:unative}__out_s{pointer:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}"({ ptr, i64 } %lit.insert8)
  %call.unpack = extractvalue { ptr } %call, 0
  store i1 true, ptr %needs.deinit9, align 1
  store ptr %call.unpack, ptr %slot, align 8
  %slot10 = load ptr, ptr %slot, align 8
  %allocator11 = load ptr, ptr %allocator, align 8
  %lit.insert12 = insertvalue { ptr, ptr } undef, ptr %slot10, 0
  %lit.insert13 = insertvalue { ptr, ptr } %lit.insert12, ptr %allocator11, 1
  %call14 = call {} @"trusted_opaque_drop__f215__in_s{slot:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},allocator:prw_s{}}__out_s{}"({ ptr, ptr } %lit.insert13)
  %i15 = load i64, ptr %i, align 4
  %add = add i64 %i15, 1
  %i16 = load i64, ptr %i, align 4
  %add17 = add i64 %i16, 1
  store i64 %add17, ptr %i, align 4
  store i1 true, ptr %needs.deinit3, align 1
  br label %while.cond

while.end:                                        ; preds = %while.cond
  %self18 = load ptr, ptr %self, align 8
  %field.addr = getelementptr inbounds nuw { { ptr, i64, { ptr, ptr } }, i64, i64 }, ptr %self18, i32 0, i32 0
  %lit.insert19 = insertvalue { ptr } undef, ptr %field.addr, 0
  %call20 = call {} @"trusted_opaque_mark_empty__f170__in_s{storage:prw_s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}}}__out_s{}"({ ptr } %lit.insert19)
  %self21 = load ptr, ptr %self, align 8
  %field.addr22 = getelementptr inbounds nuw { { ptr, i64, { ptr, ptr } }, i64, i64 }, ptr %self21, i32 0, i32 0
  %lit.insert23 = insertvalue { ptr } undef, ptr %field.addr22, 0
  %call24 = call {} @"deinit__f49__in_s{self:prw_s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}}}__out_s{}"({ ptr } %lit.insert23)
  ret {} undef
}

declare { ptr } @"reinterpret_reference__f168__in_s{base:prw_u8}__out_s{reference:pro_s{data:prw_u8,size:unative}}"({ ptr })

declare { ptr } @"reference_offset__f169__in_s{base:pro_s{data:prw_u8,size:unative},elements:unative}__out_s{reference:pro_s{data:prw_u8,size:unative}}"({ ptr, i64 })

declare { ptr } @"dynamic_array_element_ro_pointer__f167__in_s{array:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},offset:unative}__out_s{pointer:pro_s{data:prw_u8,size:unative}}"({ ptr, i64 })

declare { ptr } @"mutable_reinterpret_reference__f173__in_s{base:prw_u8}__out_s{reference:prw_s{data:prw_u8,size:unative}}"({ ptr })

declare { ptr } @"mutable_reference_offset__f174__in_s{base:prw_s{data:prw_u8,size:unative},elements:unative}__out_s{reference:prw_s{data:prw_u8,size:unative}}"({ ptr, i64 })

declare { ptr } @"dynamic_array_element_rw_pointer__f172__in_s{array:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},offset:unative}__out_s{pointer:prw_s{data:prw_u8,size:unative}}"({ ptr, i64 })

declare {} @"trusted_opaque_drop__f175__in_s{slot:prw_s{data:prw_u8,size:unative},allocator:prw_s{}}__out_s{}"({ ptr, ptr })

declare {} @"trusted_opaque_relocate__f178__in_s{source:prw_s{data:prw_u8,size:unative},destination:prw_s{data:prw_u8,size:unative}}__out_s{}"({ ptr, ptr })

declare { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"dynamic_array_grow_growing__f177__in_s{allocator:prw_s{},array:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},min_capacity:unative}__out_s{result:choice}"({ ptr, ptr, i64 })

declare {} @"trusted_opaque_move_in__f181__in_s{storage:prw_s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},destination:prw_s{data:prw_u8,size:unative},source:s{data:prw_u8,size:unative}}__out_s{}"({ ptr, ptr, { ptr, i64 } })

define {} @"deinit__f191__in_s{allocator:prw_s{},self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{}"({ ptr, ptr } %0) {
entry:
  %self = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %allocator = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  %arg = extractvalue { ptr, ptr } %0, 0
  store ptr %arg, ptr %allocator, align 8
  %arg2 = extractvalue { ptr, ptr } %0, 1
  store ptr %arg2, ptr %self, align 8
  %self3 = load ptr, ptr %self, align 8
  %field.addr = getelementptr inbounds nuw { { ptr, i64, { ptr, ptr } }, i64 }, ptr %self3, i32 0, i32 0
  %lit.insert = insertvalue { ptr } undef, ptr %field.addr, 0
  %call = call {} @"deinit__f49__in_s{self:prw_s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}}}__out_s{}"({ ptr } %lit.insert)
  ret {} undef
}

declare { ptr } @"reinterpret_reference__f200__in_s{base:pro_u8}__out_s{reference:pro_char}"({ ptr })

declare { { i32, { ptr, { ptr, i64, { ptr, ptr } } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"as_c_string__f199__in_s{self:s{data:pro_u8,length:unative},allocator:prw_s{}}__out_s{result:choice}"({ { ptr, i64 }, ptr })

declare { { i32, {}, { { i32, i8, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"buffered_writer_flush__f209__in_s{self:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative}}__out_s{result:choice}"({ ptr })

define { ptr } @"mutable_reinterpret_reference__f213__in_s{base:prw_u8}__out_s{reference:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}"({ ptr } %0) {
entry:
  %reference = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %base = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %base, align 8
  store i1 false, ptr %needs.deinit1, align 1
  %base2 = load ptr, ptr %base, align 8
  %ptr.to.int = ptrtoint ptr %base2 to i64
  %base3 = load ptr, ptr %base, align 8
  %ptr.to.int4 = ptrtoint ptr %base3 to i64
  %int.to.ptr = inttoptr i64 %ptr.to.int4 to ptr
  %base5 = load ptr, ptr %base, align 8
  %ptr.to.int6 = ptrtoint ptr %base5 to i64
  %int.to.ptr7 = inttoptr i64 %ptr.to.int6 to ptr
  store ptr %int.to.ptr7, ptr %reference, align 8
  store i1 true, ptr %needs.deinit1, align 1
  %1 = load ptr, ptr %reference, align 8
  %2 = insertvalue { ptr } undef, ptr %1, 0
  ret { ptr } %2
}

define { ptr } @"mutable_reference_offset__f214__in_s{base:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},elements:unative}__out_s{reference:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}"({ ptr, i64 } %0) {
entry:
  %address = alloca i64, align 8
  %needs.deinit15 = alloca i1, align 1
  %reference = alloca ptr, align 8
  %needs.deinit3 = alloca i1, align 1
  %elements = alloca i64, align 8
  %needs.deinit1 = alloca i1, align 1
  %base = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  %arg = extractvalue { ptr, i64 } %0, 0
  store ptr %arg, ptr %base, align 8
  %arg2 = extractvalue { ptr, i64 } %0, 1
  store i64 %arg2, ptr %elements, align 4
  store i1 false, ptr %needs.deinit3, align 1
  %base4 = load ptr, ptr %base, align 8
  %ptr.to.int = ptrtoint ptr %base4 to i64
  %elements5 = load i64, ptr %elements, align 4
  %mul = mul i64 %elements5, 40
  %base6 = load ptr, ptr %base, align 8
  %ptr.to.int7 = ptrtoint ptr %base6 to i64
  %elements8 = load i64, ptr %elements, align 4
  %mul9 = mul i64 %elements8, 40
  %add = add i64 %ptr.to.int7, %mul9
  %base10 = load ptr, ptr %base, align 8
  %ptr.to.int11 = ptrtoint ptr %base10 to i64
  %elements12 = load i64, ptr %elements, align 4
  %mul13 = mul i64 %elements12, 40
  %add14 = add i64 %ptr.to.int11, %mul13
  store i1 true, ptr %needs.deinit15, align 1
  store i64 %add14, ptr %address, align 4
  %address16 = load i64, ptr %address, align 4
  %int.to.ptr = inttoptr i64 %address16 to ptr
  %address17 = load i64, ptr %address, align 4
  %int.to.ptr18 = inttoptr i64 %address17 to ptr
  store ptr %int.to.ptr18, ptr %reference, align 8
  store i1 true, ptr %needs.deinit3, align 1
  %1 = load ptr, ptr %reference, align 8
  %2 = insertvalue { ptr } undef, ptr %1, 0
  ret { ptr } %2
}

define { ptr } @"dynamic_array_element_rw_pointer__f212__in_s{array:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},offset:unative}__out_s{pointer:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}"({ ptr, i64 } %0) {
entry:
  %base = alloca ptr, align 8
  %needs.deinit6 = alloca i1, align 1
  %pointer = alloca ptr, align 8
  %needs.deinit3 = alloca i1, align 1
  %offset = alloca i64, align 8
  %needs.deinit1 = alloca i1, align 1
  %array = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  %arg = extractvalue { ptr, i64 } %0, 0
  store ptr %arg, ptr %array, align 8
  %arg2 = extractvalue { ptr, i64 } %0, 1
  store i64 %arg2, ptr %offset, align 4
  store i1 false, ptr %needs.deinit3, align 1
  %array4 = load ptr, ptr %array, align 8
  %deref = load { { ptr, i64, { ptr, ptr } }, i64, i64 }, ptr %array4, align 8
  %fld = extractvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %deref, 0
  %fld5 = extractvalue { ptr, i64, { ptr, ptr } } %fld, 0
  %lit.insert = insertvalue { ptr } undef, ptr %fld5, 0
  %call = call { ptr } @"mutable_reinterpret_reference__f213__in_s{base:prw_u8}__out_s{reference:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}"({ ptr } %lit.insert)
  %call.unpack = extractvalue { ptr } %call, 0
  store i1 true, ptr %needs.deinit6, align 1
  store ptr %call.unpack, ptr %base, align 8
  %base7 = load ptr, ptr %base, align 8
  %offset8 = load i64, ptr %offset, align 4
  %lit.insert9 = insertvalue { ptr, i64 } undef, ptr %base7, 0
  %lit.insert10 = insertvalue { ptr, i64 } %lit.insert9, i64 %offset8, 1
  %call11 = call { ptr } @"mutable_reference_offset__f214__in_s{base:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},elements:unative}__out_s{reference:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}"({ ptr, i64 } %lit.insert10)
  %call.unpack12 = extractvalue { ptr } %call11, 0
  store ptr %call.unpack12, ptr %pointer, align 8
  store i1 true, ptr %needs.deinit3, align 1
  %1 = load ptr, ptr %pointer, align 8
  %2 = insertvalue { ptr } undef, ptr %1, 0
  ret { ptr } %2
}

define {} @"trusted_opaque_drop__f215__in_s{slot:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},allocator:prw_s{}}__out_s{}"({ ptr, ptr } %0) {
entry:
  %allocator = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %slot = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  %arg = extractvalue { ptr, ptr } %0, 0
  store ptr %arg, ptr %slot, align 8
  %arg2 = extractvalue { ptr, ptr } %0, 1
  store ptr %arg2, ptr %allocator, align 8
  %allocator3 = load ptr, ptr %allocator, align 8
  %slot4 = load ptr, ptr %slot, align 8
  %lit.insert = insertvalue { ptr, ptr } undef, ptr %allocator3, 0
  %lit.insert5 = insertvalue { ptr, ptr } %lit.insert, ptr %slot4, 1
  %call = call {} @"deinit__f191__in_s{allocator:prw_s{},self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{}"({ ptr, ptr } %lit.insert5)
  ret {} undef
}

declare {} @"trusted_opaque_move_in__f218__in_s{storage:prw_s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},destination:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},source:s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{}"({ ptr, ptr, { { ptr, i64, { ptr, ptr } }, i64 } })

declare {} @"deinit__f222__in_s{allocator:prw_s{allocation_attempts:i32,deallocations:i32,backing_freed_after_elements:bool},self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}__out_s{}"({ ptr, ptr })

declare {} @"trusted_opaque_drop__f221__in_s{slot:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},allocator:prw_s{allocation_attempts:i32,deallocations:i32,backing_freed_after_elements:bool}}__out_s{}"({ ptr, ptr })

declare {} @"deinit__f220__in_s{allocator:prw_s{allocation_attempts:i32,deallocations:i32,backing_freed_after_elements:bool},self:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative}}__out_s{}"({ ptr, ptr })

define { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"init__f223__in_s{p:prw_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},allocator:prw_s{allocation_attempts:i32,deallocations:i32,backing_freed_after_elements:bool},capacity:unative}__out_s{result:choice}"({ ptr, ptr, i64 } %0) {
entry:
  %payload = alloca { ptr, i64, { ptr, ptr } }, align 8
  %needs.deinit22 = alloca i1, align 1
  %needs.deinit23 = alloca i1, align 1
  %needs.deinit24 = alloca i1, align 1
  %needs.deinit25 = alloca i1, align 1
  %needs.deinit26 = alloca i1, align 1
  %needs.deinit27 = alloca i1, align 1
  %allocated = alloca { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, align 8
  %needs.deinit19 = alloca i1, align 1
  %bytes = alloca i64, align 8
  %needs.deinit15 = alloca i1, align 1
  %actual_capacity = alloca i64, align 8
  %needs.deinit8 = alloca i1, align 1
  %element_size = alloca i64, align 8
  %needs.deinit6 = alloca i1, align 1
  %result = alloca { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, align 8
  %needs.deinit5 = alloca i1, align 1
  %capacity = alloca i64, align 8
  %needs.deinit2 = alloca i1, align 1
  %allocator = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %p = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  store i1 false, ptr %needs.deinit2, align 1
  %arg = extractvalue { ptr, ptr, i64 } %0, 0
  store ptr %arg, ptr %p, align 8
  %arg3 = extractvalue { ptr, ptr, i64 } %0, 1
  store ptr %arg3, ptr %allocator, align 8
  %arg4 = extractvalue { ptr, ptr, i64 } %0, 2
  store i64 %arg4, ptr %capacity, align 4
  store i1 false, ptr %needs.deinit5, align 1
  store i1 true, ptr %needs.deinit6, align 1
  store i64 40, ptr %element_size, align 4
  %capacity7 = load i64, ptr %capacity, align 4
  store i1 true, ptr %needs.deinit8, align 1
  store i64 %capacity7, ptr %actual_capacity, align 4
  %actual_capacity9 = load i64, ptr %actual_capacity, align 4
  %ieq = icmp eq i64 %actual_capacity9, 0
  br i1 %ieq, label %then, label %ifend

then:                                             ; preds = %entry
  store i64 1, ptr %actual_capacity, align 4
  store i1 true, ptr %needs.deinit8, align 1
  br label %ifend

ifend:                                            ; preds = %then, %entry
  %actual_capacity10 = load i64, ptr %actual_capacity, align 4
  %element_size11 = load i64, ptr %element_size, align 4
  %mul = mul i64 %actual_capacity10, %element_size11
  %actual_capacity12 = load i64, ptr %actual_capacity, align 4
  %element_size13 = load i64, ptr %element_size, align 4
  %mul14 = mul i64 %actual_capacity12, %element_size13
  store i1 true, ptr %needs.deinit15, align 1
  store i64 %mul14, ptr %bytes, align 4
  %allocator16 = load ptr, ptr %allocator, align 8
  %bytes17 = load i64, ptr %bytes, align 4
  %lit.insert = insertvalue { ptr, i64 } undef, ptr %allocator16, 0
  %lit.insert18 = insertvalue { ptr, i64 } %lit.insert, i64 %bytes17, 1
  %call = call { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"allocate__f158__in_s{self:prw_s{allocation_attempts:i32,deallocations:i32,backing_freed_after_elements:bool},size:unative}__out_s{result:choice}"({ ptr, i64 } %lit.insert18)
  %call.unpack = extractvalue { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %call, 0
  store i1 true, ptr %needs.deinit19, align 1
  store { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %call.unpack, ptr %allocated, align 8
  %allocated20 = load { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %allocated, align 8
  store i1 false, ptr %needs.deinit19, align 1
  %match.tag = extractvalue { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %allocated20, 0
  switch i32 %match.tag, label %match.end [
    i32 0, label %match.case.0
    i32 1, label %match.case.1
  ]

match.end:                                        ; preds = %match.case.1, %match.case.0, %ifend
  %1 = load { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %result, align 8
  %2 = insertvalue { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } undef, { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %1, 0
  ret { { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %2

match.case.0:                                     ; preds = %ifend
  %allocated21 = load { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %allocated, align 8
  store i1 false, ptr %needs.deinit19, align 1
  %choice.payload = extractvalue { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %allocated21, 1
  store i1 true, ptr %needs.deinit22, align 1
  store i1 true, ptr %needs.deinit23, align 1
  store i1 true, ptr %needs.deinit24, align 1
  store i1 true, ptr %needs.deinit25, align 1
  store i1 true, ptr %needs.deinit26, align 1
  store i1 true, ptr %needs.deinit27, align 1
  store { ptr, i64, { ptr, ptr } } %choice.payload, ptr %payload, align 8
  %p28 = load ptr, ptr %p, align 8
  %payload29 = load { ptr, i64, { ptr, ptr } }, ptr %payload, align 8
  store i1 false, ptr %needs.deinit22, align 1
  store i1 false, ptr %needs.deinit23, align 1
  store i1 false, ptr %needs.deinit24, align 1
  store i1 false, ptr %needs.deinit25, align 1
  store i1 false, ptr %needs.deinit26, align 1
  store i1 false, ptr %needs.deinit27, align 1
  %actual_capacity30 = load i64, ptr %actual_capacity, align 4
  %lit.insert31 = insertvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } undef, { ptr, i64, { ptr, ptr } } %payload29, 0
  %lit.insert32 = insertvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %lit.insert31, i64 0, 1
  %lit.insert33 = insertvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %lit.insert32, i64 %actual_capacity30, 2
  store { { ptr, i64, { ptr, ptr } }, i64, i64 } %lit.insert33, ptr %p28, align 8
  store { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 0, {} undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } undef }, ptr %result, align 8
  store i1 true, ptr %needs.deinit5, align 1
  br label %match.end

match.case.1:                                     ; preds = %ifend
  store { i32, {}, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 1, {} undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } { { i32, i8 } { i32 0, i8 undef }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } { { { ptr, i64, { ptr, ptr } }, i64, i64 } { { ptr, i64, { ptr, ptr } } { ptr null, i64 0, { ptr, ptr } undef }, i64 0, i64 0 } } } }, ptr %result, align 8
  store i1 true, ptr %needs.deinit5, align 1
  br label %match.end
}

define { ptr } @"reinterpret_reference__f225__in_s{base:prw_u8}__out_s{reference:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}"({ ptr } %0) {
entry:
  %reference = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %base = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  %arg = extractvalue { ptr } %0, 0
  store ptr %arg, ptr %base, align 8
  store i1 false, ptr %needs.deinit1, align 1
  %base2 = load ptr, ptr %base, align 8
  %ptr.to.int = ptrtoint ptr %base2 to i64
  %base3 = load ptr, ptr %base, align 8
  %ptr.to.int4 = ptrtoint ptr %base3 to i64
  %int.to.ptr = inttoptr i64 %ptr.to.int4 to ptr
  %base5 = load ptr, ptr %base, align 8
  %ptr.to.int6 = ptrtoint ptr %base5 to i64
  %int.to.ptr7 = inttoptr i64 %ptr.to.int6 to ptr
  store ptr %int.to.ptr7, ptr %reference, align 8
  store i1 true, ptr %needs.deinit1, align 1
  %1 = load ptr, ptr %reference, align 8
  %2 = insertvalue { ptr } undef, ptr %1, 0
  ret { ptr } %2
}

define { ptr } @"reference_offset__f226__in_s{base:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},elements:unative}__out_s{reference:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}"({ ptr, i64 } %0) {
entry:
  %address = alloca i64, align 8
  %needs.deinit15 = alloca i1, align 1
  %reference = alloca ptr, align 8
  %needs.deinit3 = alloca i1, align 1
  %elements = alloca i64, align 8
  %needs.deinit1 = alloca i1, align 1
  %base = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  %arg = extractvalue { ptr, i64 } %0, 0
  store ptr %arg, ptr %base, align 8
  %arg2 = extractvalue { ptr, i64 } %0, 1
  store i64 %arg2, ptr %elements, align 4
  store i1 false, ptr %needs.deinit3, align 1
  %base4 = load ptr, ptr %base, align 8
  %ptr.to.int = ptrtoint ptr %base4 to i64
  %elements5 = load i64, ptr %elements, align 4
  %mul = mul i64 %elements5, 40
  %base6 = load ptr, ptr %base, align 8
  %ptr.to.int7 = ptrtoint ptr %base6 to i64
  %elements8 = load i64, ptr %elements, align 4
  %mul9 = mul i64 %elements8, 40
  %add = add i64 %ptr.to.int7, %mul9
  %base10 = load ptr, ptr %base, align 8
  %ptr.to.int11 = ptrtoint ptr %base10 to i64
  %elements12 = load i64, ptr %elements, align 4
  %mul13 = mul i64 %elements12, 40
  %add14 = add i64 %ptr.to.int11, %mul13
  store i1 true, ptr %needs.deinit15, align 1
  store i64 %add14, ptr %address, align 4
  %address16 = load i64, ptr %address, align 4
  %int.to.ptr = inttoptr i64 %address16 to ptr
  %address17 = load i64, ptr %address, align 4
  %int.to.ptr18 = inttoptr i64 %address17 to ptr
  store ptr %int.to.ptr18, ptr %reference, align 8
  store i1 true, ptr %needs.deinit3, align 1
  %1 = load ptr, ptr %reference, align 8
  %2 = insertvalue { ptr } undef, ptr %1, 0
  ret { ptr } %2
}

define { ptr } @"dynamic_array_element_ro_pointer__f224__in_s{array:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative,capacity:unative},offset:unative}__out_s{pointer:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}"({ ptr, i64 } %0) {
entry:
  %base = alloca ptr, align 8
  %needs.deinit6 = alloca i1, align 1
  %pointer = alloca ptr, align 8
  %needs.deinit3 = alloca i1, align 1
  %offset = alloca i64, align 8
  %needs.deinit1 = alloca i1, align 1
  %array = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  %arg = extractvalue { ptr, i64 } %0, 0
  store ptr %arg, ptr %array, align 8
  %arg2 = extractvalue { ptr, i64 } %0, 1
  store i64 %arg2, ptr %offset, align 4
  store i1 false, ptr %needs.deinit3, align 1
  %array4 = load ptr, ptr %array, align 8
  %deref = load { { ptr, i64, { ptr, ptr } }, i64, i64 }, ptr %array4, align 8
  %fld = extractvalue { { ptr, i64, { ptr, ptr } }, i64, i64 } %deref, 0
  %fld5 = extractvalue { ptr, i64, { ptr, ptr } } %fld, 0
  %lit.insert = insertvalue { ptr } undef, ptr %fld5, 0
  %call = call { ptr } @"reinterpret_reference__f225__in_s{base:prw_u8}__out_s{reference:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}"({ ptr } %lit.insert)
  %call.unpack = extractvalue { ptr } %call, 0
  store i1 true, ptr %needs.deinit6, align 1
  store ptr %call.unpack, ptr %base, align 8
  %base7 = load ptr, ptr %base, align 8
  %offset8 = load i64, ptr %offset, align 4
  %lit.insert9 = insertvalue { ptr, i64 } undef, ptr %base7, 0
  %lit.insert10 = insertvalue { ptr, i64 } %lit.insert9, i64 %offset8, 1
  %call11 = call { ptr } @"reference_offset__f226__in_s{base:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},elements:unative}__out_s{reference:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative}}"({ ptr, i64 } %lit.insert10)
  %call.unpack12 = extractvalue { ptr } %call11, 0
  store ptr %call.unpack12, ptr %pointer, align 8
  store i1 true, ptr %needs.deinit3, align 1
  %1 = load ptr, ptr %pointer, align 8
  %2 = insertvalue { ptr } undef, ptr %1, 0
  ret { ptr } %2
}

define { { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"copy__f227__in_s{self:pro_s{allocation:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},length:unative},allocator:prw_s{allocation_attempts:i32,deallocations:i32,backing_freed_after_elements:bool}}__out_s{result:choice}"({ ptr, ptr } %0) {
entry:
  %src_view = alloca { ptr, i64 }, align 8
  %needs.deinit60 = alloca i1, align 1
  %needs.deinit61 = alloca i1, align 1
  %needs.deinit62 = alloca i1, align 1
  %dst_view = alloca { ptr, i64 }, align 8
  %needs.deinit45 = alloca i1, align 1
  %needs.deinit46 = alloca i1, align 1
  %needs.deinit47 = alloca i1, align 1
  %out = alloca { { ptr, i64, { ptr, ptr } }, i64 }, align 8
  %needs.deinit28 = alloca i1, align 1
  %needs.deinit29 = alloca i1, align 1
  %needs.deinit30 = alloca i1, align 1
  %needs.deinit31 = alloca i1, align 1
  %needs.deinit32 = alloca i1, align 1
  %needs.deinit33 = alloca i1, align 1
  %needs.deinit34 = alloca i1, align 1
  %needs.deinit35 = alloca i1, align 1
  %payload = alloca { ptr, i64, { ptr, ptr } }, align 8
  %needs.deinit16 = alloca i1, align 1
  %needs.deinit17 = alloca i1, align 1
  %needs.deinit18 = alloca i1, align 1
  %needs.deinit19 = alloca i1, align 1
  %needs.deinit20 = alloca i1, align 1
  %needs.deinit21 = alloca i1, align 1
  %allocated = alloca { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, align 8
  %needs.deinit13 = alloca i1, align 1
  %allocation_size = alloca i64, align 8
  %needs.deinit9 = alloca i1, align 1
  %result = alloca { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, align 8
  %needs.deinit3 = alloca i1, align 1
  %allocator = alloca ptr, align 8
  %needs.deinit1 = alloca i1, align 1
  %self = alloca ptr, align 8
  %needs.deinit = alloca i1, align 1
  store i1 false, ptr %needs.deinit, align 1
  store i1 false, ptr %needs.deinit1, align 1
  %arg = extractvalue { ptr, ptr } %0, 0
  store ptr %arg, ptr %self, align 8
  %arg2 = extractvalue { ptr, ptr } %0, 1
  store ptr %arg2, ptr %allocator, align 8
  store i1 false, ptr %needs.deinit3, align 1
  %self4 = load ptr, ptr %self, align 8
  %deref = load { { ptr, i64, { ptr, ptr } }, i64 }, ptr %self4, align 8
  %fld = extractvalue { { ptr, i64, { ptr, ptr } }, i64 } %deref, 1
  %add = add i64 %fld, 1
  %self5 = load ptr, ptr %self, align 8
  %deref6 = load { { ptr, i64, { ptr, ptr } }, i64 }, ptr %self5, align 8
  %fld7 = extractvalue { { ptr, i64, { ptr, ptr } }, i64 } %deref6, 1
  %add8 = add i64 %fld7, 1
  store i1 true, ptr %needs.deinit9, align 1
  store i64 %add8, ptr %allocation_size, align 4
  %allocator10 = load ptr, ptr %allocator, align 8
  %allocation_size11 = load i64, ptr %allocation_size, align 4
  %lit.insert = insertvalue { ptr, i64 } undef, ptr %allocator10, 0
  %lit.insert12 = insertvalue { ptr, i64 } %lit.insert, i64 %allocation_size11, 1
  %call = call { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } @"allocate__f158__in_s{self:prw_s{allocation_attempts:i32,deallocations:i32,backing_freed_after_elements:bool},size:unative}__out_s{result:choice}"({ ptr, i64 } %lit.insert12)
  %call.unpack = extractvalue { { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %call, 0
  store i1 true, ptr %needs.deinit13, align 1
  store { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %call.unpack, ptr %allocated, align 8
  %allocated14 = load { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %allocated, align 8
  store i1 false, ptr %needs.deinit13, align 1
  %match.tag = extractvalue { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %allocated14, 0
  switch i32 %match.tag, label %match.end [
    i32 1, label %match.case.0
    i32 0, label %match.case.1
  ]

match.end:                                        ; preds = %ifend, %entry
  %1 = load { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %result, align 8
  %2 = insertvalue { { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } undef, { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %1, 0
  ret { { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %2

match.case.0:                                     ; preds = %entry
  store { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 1, { { ptr, i64, { ptr, ptr } }, i64 } undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } { { i32, i8 } { i32 0, i8 undef }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } { { { ptr, i64, { ptr, ptr } }, i64, i64 } { { ptr, i64, { ptr, ptr } } { ptr null, i64 0, { ptr, ptr } undef }, i64 0, i64 0 } } } }, ptr %result, align 8
  store i1 true, ptr %needs.deinit3, align 1
  %3 = load { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %result, align 8
  %4 = insertvalue { { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } undef, { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %3, 0
  ret { { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } } %4

match.case.1:                                     ; preds = %entry
  %allocated15 = load { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } }, ptr %allocated, align 8
  store i1 false, ptr %needs.deinit13, align 1
  %choice.payload = extractvalue { i32, { ptr, i64, { ptr, ptr } }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %allocated15, 1
  store i1 true, ptr %needs.deinit16, align 1
  store i1 true, ptr %needs.deinit17, align 1
  store i1 true, ptr %needs.deinit18, align 1
  store i1 true, ptr %needs.deinit19, align 1
  store i1 true, ptr %needs.deinit20, align 1
  store i1 true, ptr %needs.deinit21, align 1
  store { ptr, i64, { ptr, ptr } } %choice.payload, ptr %payload, align 8
  %payload22 = load { ptr, i64, { ptr, ptr } }, ptr %payload, align 8
  store i1 false, ptr %needs.deinit16, align 1
  store i1 false, ptr %needs.deinit17, align 1
  store i1 false, ptr %needs.deinit18, align 1
  store i1 false, ptr %needs.deinit19, align 1
  store i1 false, ptr %needs.deinit20, align 1
  store i1 false, ptr %needs.deinit21, align 1
  %self23 = load ptr, ptr %self, align 8
  %deref24 = load { { ptr, i64, { ptr, ptr } }, i64 }, ptr %self23, align 8
  %fld25 = extractvalue { { ptr, i64, { ptr, ptr } }, i64 } %deref24, 1
  %lit.insert26 = insertvalue { { ptr, i64, { ptr, ptr } }, i64 } undef, { ptr, i64, { ptr, ptr } } %payload22, 0
  %lit.insert27 = insertvalue { { ptr, i64, { ptr, ptr } }, i64 } %lit.insert26, i64 %fld25, 1
  store i1 true, ptr %needs.deinit28, align 1
  store i1 true, ptr %needs.deinit29, align 1
  store i1 true, ptr %needs.deinit30, align 1
  store i1 true, ptr %needs.deinit31, align 1
  store i1 true, ptr %needs.deinit32, align 1
  store i1 true, ptr %needs.deinit33, align 1
  store i1 true, ptr %needs.deinit34, align 1
  store i1 true, ptr %needs.deinit35, align 1
  store { { ptr, i64, { ptr, ptr } }, i64 } %lit.insert27, ptr %out, align 8
  %allocation_size36 = load i64, ptr %allocation_size, align 4
  %igt = icmp ugt i64 %allocation_size36, 0
  br i1 %igt, label %then, label %ifend

then:                                             ; preds = %match.case.1
  %out37 = load { { ptr, i64, { ptr, ptr } }, i64 }, ptr %out, align 8
  %fld38 = extractvalue { { ptr, i64, { ptr, ptr } }, i64 } %out37, 0
  %fld39 = extractvalue { ptr, i64, { ptr, ptr } } %fld38, 0
  %allocation_size40 = load i64, ptr %allocation_size, align 4
  %lit.insert41 = insertvalue { ptr, i64 } undef, ptr %fld39, 0
  %lit.insert42 = insertvalue { ptr, i64 } %lit.insert41, i64 %allocation_size40, 1
  %call43 = call { { ptr, i64 } } @"array_view__f189__in_s{data:prw_u8,length:unative}__out_s{array:s{data:prw_u8,length:unative}}"({ ptr, i64 } %lit.insert42)
  %call.unpack44 = extractvalue { { ptr, i64 } } %call43, 0
  store i1 true, ptr %needs.deinit45, align 1
  store i1 true, ptr %needs.deinit46, align 1
  store i1 true, ptr %needs.deinit47, align 1
  store { ptr, i64 } %call.unpack44, ptr %dst_view, align 8
  %self48 = load ptr, ptr %self, align 8
  %deref49 = load { { ptr, i64, { ptr, ptr } }, i64 }, ptr %self48, align 8
  %fld50 = extractvalue { { ptr, i64, { ptr, ptr } }, i64 } %deref49, 0
  %fld51 = extractvalue { ptr, i64, { ptr, ptr } } %fld50, 0
  %lit.insert52 = insertvalue { ptr } undef, ptr %fld51, 0
  %call53 = call { ptr } @"read_reference__f188__in_s{base:prw_u8}__out_s{reference:pro_u8}"({ ptr } %lit.insert52)
  %call.unpack54 = extractvalue { ptr } %call53, 0
  %allocation_size55 = load i64, ptr %allocation_size, align 4
  %lit.insert56 = insertvalue { ptr, i64 } undef, ptr %call.unpack54, 0
  %lit.insert57 = insertvalue { ptr, i64 } %lit.insert56, i64 %allocation_size55, 1
  %call58 = call { { ptr, i64 } } @"array_view_ro__f192__in_s{data:pro_u8,length:unative}__out_s{array:s{data:pro_u8,length:unative}}"({ ptr, i64 } %lit.insert57)
  %call.unpack59 = extractvalue { { ptr, i64 } } %call58, 0
  store i1 true, ptr %needs.deinit60, align 1
  store i1 true, ptr %needs.deinit61, align 1
  store i1 true, ptr %needs.deinit62, align 1
  store { ptr, i64 } %call.unpack59, ptr %src_view, align 8
  %dst_view63 = load { ptr, i64 }, ptr %dst_view, align 8
  %src_view64 = load { ptr, i64 }, ptr %src_view, align 8
  %lit.insert65 = insertvalue { { ptr, i64 }, { ptr, i64 } } undef, { ptr, i64 } %dst_view63, 0
  %lit.insert66 = insertvalue { { ptr, i64 }, { ptr, i64 } } %lit.insert65, { ptr, i64 } %src_view64, 1
  %call67 = call {} @"memcpy_bytes__f39__in_s{dst:s{data:prw_u8,length:unative},src:s{data:pro_u8,length:unative}}__out_s{}"({ { ptr, i64 }, { ptr, i64 } } %lit.insert66)
  br label %ifend

ifend:                                            ; preds = %then, %match.case.1
  %out68 = load { { ptr, i64, { ptr, ptr } }, i64 }, ptr %out, align 8
  store i1 false, ptr %needs.deinit28, align 1
  store i1 false, ptr %needs.deinit29, align 1
  store i1 false, ptr %needs.deinit30, align 1
  store i1 false, ptr %needs.deinit31, align 1
  store i1 false, ptr %needs.deinit32, align 1
  store i1 false, ptr %needs.deinit33, align 1
  store i1 false, ptr %needs.deinit34, align 1
  store i1 false, ptr %needs.deinit35, align 1
  %choice.payload69 = insertvalue { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } { i32 0, { { ptr, i64, { ptr, ptr } }, i64 } undef, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } undef }, { { ptr, i64, { ptr, ptr } }, i64 } %out68, 1
  store { i32, { { ptr, i64, { ptr, ptr } }, i64 }, { { i32, i8 }, { { { ptr, i64, { ptr, ptr } }, i64, i64 } } } } %choice.payload69, ptr %result, align 8
  store i1 true, ptr %needs.deinit3, align 1
  br label %match.end
}

declare i64 @__argi_runtime_argc()

declare i64 @__argi_runtime_argv()

define i32 @main(i32 %0, ptr %1) {
entry:
  %argc.native = zext i32 %0 to i64
  store i64 %argc.native, ptr @__argi_runtime_argc_global, align 4
  %argv.native = ptrtoint ptr %1 to i64
  store i64 %argv.native, ptr @__argi_runtime_argv_global, align 4
  %main.ctor.tmp = alloca { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, align 8
  %main.ctor.arg.p = insertvalue { ptr } undef, ptr %main.ctor.tmp, 0
  %2 = call {} @"init__f147__in_s{p:prw_s{_storage:s{allocator:s{},terminal:s{_storage:s{stdin_file:s{stream_address:unative,should_close:bool},stdout_file:s{stream_address:unative,should_close:bool},stderr_file:s{stream_address:unative,should_close:bool},stdin_reader:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative}},stdin_file:prw_s{stream_address:unative,should_close:bool},stdout_file:prw_s{stream_address:unative,should_close:bool},stderr_file:prw_s{stream_address:unative,should_close:bool},stdin_reader:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stdin:prw_abs_Reader,stdout:prw_abs_Writer,stderr:prw_abs_Writer},args:s{count:unative,address:unative},env_vars:s{},file_sys:s{},network:s{},proc_man:s{},clock:s{},rand_gen:s{},ffi:s{}},allocator:prw_s{},terminal:prw_s{_storage:s{stdin_file:s{stream_address:unative,should_close:bool},stdout_file:s{stream_address:unative,should_close:bool},stderr_file:s{stream_address:unative,should_close:bool},stdin_reader:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative}},stdin_file:prw_s{stream_address:unative,should_close:bool},stdout_file:prw_s{stream_address:unative,should_close:bool},stderr_file:prw_s{stream_address:unative,should_close:bool},stdin_reader:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stdin:prw_abs_Reader,stdout:prw_abs_Writer,stderr:prw_abs_Writer},args:prw_s{count:unative,address:unative},env_vars:prw_s{},file_sys:prw_s{},network:prw_s{},proc_man:prw_s{},clock:prw_s{},rand_gen:prw_s{},ffi:prw_s{}}}__out_s{}"({ ptr } %main.ctor.arg.p)
  %main.ctor.load = load { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, ptr %main.ctor.tmp, align 8
  %main.default = insertvalue { { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr } } undef, { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr } %main.ctor.load, 0
  %main.call = call { i32 } @"main__f160__in_s{system:s{_storage:s{allocator:s{},terminal:s{_storage:s{stdin_file:s{stream_address:unative,should_close:bool},stdout_file:s{stream_address:unative,should_close:bool},stderr_file:s{stream_address:unative,should_close:bool},stdin_reader:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative}},stdin_file:prw_s{stream_address:unative,should_close:bool},stdout_file:prw_s{stream_address:unative,should_close:bool},stderr_file:prw_s{stream_address:unative,should_close:bool},stdin_reader:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stdin:prw_abs_Reader,stdout:prw_abs_Writer,stderr:prw_abs_Writer},args:s{count:unative,address:unative},env_vars:s{},file_sys:s{},network:s{},proc_man:s{},clock:s{},rand_gen:s{},ffi:s{}},allocator:prw_s{},terminal:prw_s{_storage:s{stdin_file:s{stream_address:unative,should_close:bool},stdout_file:s{stream_address:unative,should_close:bool},stderr_file:s{stream_address:unative,should_close:bool},stdin_reader:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative}},stdin_file:prw_s{stream_address:unative,should_close:bool},stdout_file:prw_s{stream_address:unative,should_close:bool},stderr_file:prw_s{stream_address:unative,should_close:bool},stdin_reader:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,start:unative,end:unative},stdout_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stderr_writer:prw_s{base:prw_s{stream_address:unative,should_close:bool},buffer:s{data:prw_u8,size:unative,deallocator:s{data:prw_any,vtable:pro_any}},capacity:unative,length:unative},stdin:prw_abs_Reader,stdout:prw_abs_Writer,stderr:prw_abs_Writer},args:prw_s{count:unative,address:unative},env_vars:prw_s{},file_sys:prw_s{},network:prw_s{},proc_man:prw_s{},clock:prw_s{},rand_gen:prw_s{},ffi:prw_s{}}}__out_s{status_code:i32}"({ { { {}, { { { i64, i1 }, { i64, i1 }, { i64, i1 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 }, { ptr, { ptr, i64, { ptr, ptr } }, i64, i64 } }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr }, { i64, i64 }, {}, {}, {}, {}, {}, {}, {} }, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr } } %main.default)
  %main.status = extractvalue { i32 } %main.call, 0
  ret i32 %main.status
}
