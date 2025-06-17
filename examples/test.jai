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
        // Utils tests
        {
            // string_to_u64 from Utils
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
            
            // parse_number from Utils
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
        }
        
        // GON tests 
        {
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

