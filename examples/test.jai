#import "Basic"()(MEMORY_DEBUGGER=true);
#import "File";
#import "Math";
#import "Reflection";

#import "Utils";
Convert :: #import "Convert";

#import "GON"()();

Thing :: struct {
    name:       string;
    numbers:    [5] int;
    fraction:   float;
    text:       string;
    flags:      Flags;
    fruit:      Fruits;
}

Flags :: enum_flags {
    FIRST;
    SECOND;
    THIRD;
}

Fruits :: enum {
    APPLE;
    PEAR;
    BANANA;
    STRAWBERRY;
    KIWI;
}

main :: () {
    // UA :: #import "Unmapping_Allocator";
    // context.allocator = UA.get_unmapping_allocator();
    {
        #if true {
            things: [] Thing;
            defer {
                for *things {
                    free(it.text);
                    free(it.name);
                }
                array_free(things);
            }
            
            add_io_data(Thing, .{
                name_member = get_field(type_info(Thing), "name"),
                flags = .SKIP_ELEMS_IF_EMPTY
            });
            
            file, ok := read_entire_file("test.gon");
            defer free(file);
            if !ok return;
            
            parser:, ok = parse_file(file);
            defer deinit_parser(*parser);
            if !ok return;
            
            add_data_binding(*parser, things, "things");
            
            if !process_data_bindings(*parser) {
                log("failed to process data bindings");
                return;
            }
            
            {
                serializer: Parser;
                init_parser(*serializer, "");
                insert_data_node(*serializer, null, "things", things);
                
                output, ok := serialize_to_string(*serializer);
                // output, ok := serialize_to_string(*parser);
                defer free(output);
                if ok  print("%\n", output);
                
                write_entire_file("test_output.gon", output);
            }
            
            print("%\n", things);
        }
        
        // test cases
        #if true {
            {
                test_string_to_u64 :: (str: string, base: u64) {
                    val, ok, remainder := string_to_u64(str, base);
                    print("string_to_u64(\"%\", %) -> %, %, \"%\"\n", str, base, val, ok, remainder);
                }
                
                test_string_to_u64("69420", 10);
                
                str := tprint("%", U64_MAX);
                test_string_to_u64(str, 10);
                
                str[str.count-1] += 1;
                test_string_to_u64(str, 10);
                
                test_string_to_u64("fF", 16);
            }
            
            {
                test_parse_number :: (str: string) {
                    print("string_to_u64(\"%\")\n", str);
                    val, ok := parse_number(str);
                    if ok {
                        print("\t-> % %\n", as_type(val.type), to_any(*val));
                    } else {
                        print("\t-> FAILED\n");
                    }
                }
    
                test_parse_number("35");
                test_parse_number("-97");
                
                str := tprint("%", S64_MAX);
                test_parse_number(str);
                
                str[str.count-1] += 1;
                test_parse_number(str);
                
                test_parse_number("3.14159");
                test_parse_number("-420.69");
                
                test_parse_number("0x");
                
                test_parse_number("0x00F");
                test_parse_number("0x200");
            }
            
            // TODO: generate table of string values for integer max/min sizes and numbers just outside of ranges
            // test all integer test limits of range, inside and out
            for NUMBER_LIMITS {
                info := it.type.(*Type_Info_Integer);
                
                test :: (ti: *Type_Info, str: string, expect_success: bool) {
                    number := Any_Number.{ type = ti };
                    log("\t\tinput string: '%'", str);
                    if Convert.set_value_from_string(to_any(*number), str) == expect_success {
                        log("\t\tTEST PASSED");
                    } else {
                        log("\t\tTEST FAILED");
                    }
                    log("\t\toutput_value: % %", as_type(number.type), to_any(*number));
                }
                
                log("test %", it.type);
                
                log("\tmin");     test(info, it.min,           true);
                log("\tmin-1");   test(info, it.min_minus_one, false);
                log("\tmax");     test(info, it.max,           true);
                log("\tmax+1");   test(info, it.max_plus_one,  false);
                
                // if info.signed {
                //     // low, high := signed_integer_range_from_size(info.runtime_size);
                //     log("TEST % min",   type); assert(set_value_from_string(to_any(*number), tprint("%", it.min          ) == true );
                //     log("TEST % min-1", type); assert(set_value_from_string(to_any(*number), tprint("%", it.min_minus_one) == false);
                //     log("TEST % max",   type); assert(set_value_from_string(to_any(*number), tprint("%", it.max          ) == true );
                //     log("TEST % max+1", type); assert(set_value_from_string(to_any(*number), tprint("%", it.max_plus_one ) == false);
                // } else {
                //     // low, high := unsigned_integer_range_from_size(info.runtime_size);
                //     log("TEST % min",   type); assert(set_value_from_string(to_any(*number), tprint("%",  it.min          ) == true );
                //     log("TEST % min-1", type); assert(set_value_from_string(to_any(*number), tprint("%",  it.min_minus_one) == false);
                //     log("TEST % max",   type); assert(set_value_from_string(to_any(*number), tprint("%",  it.max          ) == true );
                //     log("TEST % max+1", type); assert(set_value_from_string(to_any(*number), tprint("%",  it.max_plus_one ) == false);
                // }
            }
            
            // test float and double
            _float32: float32;
            assert(Convert.set_value_from_string(_float32, "3") == true);
            assert(Convert.set_value_from_string(_float32, "3.5") == true);
            assert(Convert.set_value_from_string(_float32, "text") == false);
            assert(Convert.set_value_from_string(_float32, "3.5text") == false);
            assert(Convert.set_value_from_string(_float32, "text3.5") == false);
            assert(Convert.set_value_from_string(_float32, "3.5.5") == false);
            
            _float64: float64;
            assert(Convert.set_value_from_string(_float64, "3") == true);
            assert(Convert.set_value_from_string(_float64, "3.5") == true);
            assert(Convert.set_value_from_string(_float64, "text") == false);
            assert(Convert.set_value_from_string(_float64, "3.5text") == false);
            assert(Convert.set_value_from_string(_float64, "text3.5") == false);
            assert(Convert.set_value_from_string(_float64, "3.5.5") == false);
            
            // test enum and enum_flags
            
            
            
            
            
            // test custom parsing callback for structs and arrays
            
            // test io data for name member of struct
            
            // test indexed array
            
            // test enum-indexed array
            
            // test struct -> GON array
            // test struct -> GON object
            
            // test array -> GON array
            // test array -> GON object
                // if no defined struct name member, or element type not struct, should fail
        }
    }
    report_memory_leaks();
}



NUMBER_LIMITS :: struct { 
    type:           Type;
    min:            string;
    min_minus_one:  string;
    max:            string;
    max_plus_one:   string;
}.[
    .{ u\8, "0", "-1",                  "255",                  "256" },
    .{ u16, "0", "-1",                "65535",                "65536" },
    .{ u32, "0", "-1",           "4294967295",           "4294967296" },
    .{ u64, "0", "-1", "18446744073709551615", "18446744073709551616" },
    
    .{ s\8,                 "-128",                 "-129",                 "127",                 "128" },
    .{ s16,               "-32768",               "-32769",               "32767",               "32768" },
    .{ s32,          "-2147483648",          "-2147483649",          "2147483647",          "2147483648" },
    .{ s64, "-9223372036854775808", "-9223372036854775809", "9223372036854775807", "9223372036854775808" },
];