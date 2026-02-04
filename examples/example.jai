#import "Basic";
#import "File";
#import "Math";
#import "Reflection";
#import "String";

#import "GON"()(LANGUAGES=string.["JSON"]);

main :: () {
    
    TEST_GON :: true;
    
    write_string("===== Example 1: the basics =====\n");
    {
        // Suppose we have the following JSON file:
        file :: #string END
        "my_int": 5,
        "foo": {
            "my_float":   3.5,
            "my_string":  "this is a string"
        }
        END
        
        
        model: Data_Model;
        init_data_model(*model);
        defer deinit_data_model(*model);
        
        model.language = JSON_get_language();
        
        ok := parse_file(*model, file, "Example 1");
        if !ok  return;
        
        // Now we want to extract some information from this file into the following variables:
        my_int:     int;
        my_float:   float;
        my_string:  string;
        
        // So we create data bindings with the variables and the path to the data in the file:
        ok = add_data_bindings(*model, 
            .{ my_int,    "my_int"        },
            .{ my_float,  "foo/my_float"  },
            .{ my_string, "foo/my_string" },
        );
        if !ok  return;
        
        // After processing our data bindings, the variables we bound will have their values filled in.
        ok = process_data_bindings(*model);
        if !ok  return;
        
        
        print("my_int:    %\n", my_int);
        print("my_float:  %\n", my_float);
        print("my_string: \"%\"\n", my_string);
    }
    write_string("\n\n");
    
    
    // write_string("===== Example 2: structs and arrays =====\n");
    
    my_io_data: IO_Data_Table;
    defer reset(*my_io_data);
    
    Thing :: struct {
        name:       string;
        text:       string;
        numbers:    [5] int;
        position:   Vector3;
        flags:      Flags;
        
        Flags :: enum_flags { FIRST; SECOND; THIRD; }
    }
    
    things:  [] Thing;
    
    defer {
        for *things {
            free(it.text);
            free(it.name);
        }
        array_free(things);
    }
    
    add_io_data(*my_io_data, Thing, .{
        get_name = (value: Any) -> string { 
            if value.type != xx Thing  return "";
            return value.value_pointer.(*Thing).name;
        },
        set_name = (value: Any, name: string) { 
            if value.type != xx Thing  return;
            name_pointer := *value.value_pointer.(*Thing).name;
            if name_pointer.* == "" {
                name_pointer.* = copy_string(name);
            }
        },
        
        flags = .SKIP_ELEMS_IF_EMPTY
    });
    
    {
        file_path := "example.gon";
        file, ok := read_entire_file(file_path);
        if !ok  return;
        
        model: Data_Model;
        init_data_model(*model);
        defer deinit_data_model(*model);
        
        model.io_data_table = *my_io_data;
        model.language = JSON_get_language(.{json_flags = JSON_Config.Flags.DEFAULT_GON_FLAGS});
        
        ok = parse_file(*model, file, file_path);
        if !ok  return;
        
        if !add_data_binding(*model, things, "things")  return;
        
        if !process_data_bindings(*model)  return;
    }
    
    // Setting print_style to use newlines, so the data is more legible, 
    // and we can more easily compare to the re-serialized GON output below.
    context.print_style.default_format_struct.use_newlines_if_long_form = true;
    context.print_style.default_format_struct.use_long_form_if_more_than_this_many_members = -1;
    
    print("Behold, the things we parsed:\n%\n", things);
    
    write_string("\n\n");
    
    
    // write_string("===== Example 3: indexed arrays and custom parsing =====\n");
    
    // /*
    //     Indexed and enumerated arrays can be very helpful for lookup tables and the like.
    //     In this example we have some enum `Fruits` which indexes a lookup table `fruit_facts`.
    // */
    // Fruits :: enum {
    //     APPLE;
    //     PEAR;
    //     BANANA;
    //     STRAWBERRY;
    //     KIWI;
        
    //     _COUNT;
    // }
    
    // fruit_facts: [Fruits._COUNT] struct {
    //     nutrition:    int;
    //     flavor:       int;
    //     description:  string;
    // };
    
    // add_io_data(type_of(fruit_facts), .{
    //     flags = .IS_INDEXED_ARRAY,
    //     enum_index_type = xx Fruits
    // });
    
    // // For compactness, serialize the elements in GON array format.
    // add_io_data(type_of(fruit_facts[0]), .{ flags = .SERIALIZE_AS_ARRAY, });
    
    
    
    // /*
    //     Custom parsing and serialization procs.
    //     This is a bit of a contrived example, but I wanted to keep it simple.
    //     A more realistic example may be something like a DateTime value that you want to have in a human-readable string in the GON file, but is stored internally as Apollo_Time.
    //     You can just plug in the code to adapt it to/from a string and then you don't have to worry about post-processing your data after loading it in from a file.
    // */
    // CSV :: [] string;
    
    // string_to_csv :: (val: Any, str: string) -> bool {
    //     assert(val.type == xx CSV);
    //     csv := val.value_pointer.(*CSV);
    //     csv.* = split(str, ",".(u8));
        
    //     // We must copy all of these individual strings, since the underlying file will get freed.
    //     for *(csv.*)  it.* = copy_string(it.*);
    //     return true;
    // }
    
    // csv_to_string :: (val: Any) -> bool, string {
    //     assert(val.type == xx CSV);
    //     csv := val.value_pointer.(*CSV);
        
    //     // We allocate the output string with temp since GON won't free it for us.
    //     str := join(..csv.*, separator = ",",, temp);
    //     return true, str;
    // }
    
    // csv: CSV;
    
    // add_io_data(CSV, .{
    //     parse_proc     = string_to_csv,
    //     serialize_proc = csv_to_string
    // });
    
    
    
    // // Cute little one-liner! (Using the same file as the previous example.)
    // // Notice in example.gon that 
    // ok := load_and_parse_file_with_bindings("example.gon", 
    //     .{ csv,         "foo/csv" },
    //     .{ fruit_facts, "foo/bar/fruit_facts" },
    // );
    // if !ok  return;
    
    
    // print("fruit_facts:\n%\n\n", fruit_facts);
    // print("csv:\n%\n", csv);
    
    // write_string("\n\n");
    
    
    {
        write_string("===== Example 4: Serialization =====\n");
        
        model: Data_Model;
        init_data_model(*model);
        defer deinit_data_model(*model);
        
        model.io_data_table = *my_io_data;
        model.language = JSON_get_language(.{json_flags = JSON_Config.Flags.DEFAULT_GON_FLAGS});
        
        // Uncomment this line to see Vector3 serialized as a GON array instead of a GON object.
        add_io_data(*my_io_data, Vector3, .{ preferred_node_kind_for_serialization = .ARRAY });
        
        // Like add_data_bindings, this procedure works recursively, 
        // generating DOM nodes for every single array element and member variable.
        insert_node_with_binding(*model, null, "things", things);
        // insert_node_with_binding(*model, null, "foo/bar/fruit_facts", fruit_facts);
        // insert_node_with_binding(*model, null, "foo/csv", csv);
        
        ok, output := serialize_to_string(*model);
        if !ok  return;
        defer free(output);
        
        print("Behold, the GON ouput we serialized:\n%\n", output);
        
        // Uncomment this line to output to a file:
        // serialize_to_file(*parser, "example_output.gon");
        write_string("\n\n");
    }
}
