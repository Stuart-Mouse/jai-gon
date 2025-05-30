#import "Basic"()(MEMORY_DEBUGGER=true);
#import "File";
#import "Math";
#import "Reflection";

#import "GON";
#import "Utils";
Convert :: #import "Convert";


main :: () {
    // UA :: #import "Unmapping_Allocator";
    // context.allocator = UA.get_unmapping_allocator();
    {
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


/*
    Using the string values for all the numbers here is maybe kind of silly, but hey it works...
*/
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