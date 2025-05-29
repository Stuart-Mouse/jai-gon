#import "Basic";
#import "File";
#import "Math";
#import "Reflection";
#import "String";

#import "GON";

Thing :: struct {
    name:       string;
    text:       string;
    numbers:    [5] int;
    position:   Vector3;
    flags:      Flags;
}

Flags :: enum_flags {
    FIRST;
    SECOND;
    THIRD;
}


// to demonstrate custom parsing and serialization procs
CSV :: [] string;

string_to_csv :: (val: Any, str: string) -> bool {
    assert(val.type == xx CSV);
    csv := val.value_pointer.(*CSV);
    csv.* = split(str, ",".(u8));
    return true;
}

csv_to_string :: (val: Any) -> string, bool {
    assert(val.type == xx CSV);
    csv := val.value_pointer.(*CSV);
    return join(..csv.*, separator = ","), true;
}



// to demonstrate enum-indexed arrays
Fruits :: enum {
    APPLE;
    PEAR;
    BANANA;
    STRAWBERRY;
    KIWI;
    
    _COUNT;
}

Fruit_Facts :: [Fruits._COUNT] struct {
    nutrition:    int;
    flavor:       int;
    description:  string;
};



main :: () {
    // This array and everything within it will get filled in by the parser.
    // (You can also change this to a resizable array, and it will work the same.)
    things:      [] Thing;
    
    // For the sake of setting a good example, let's clean up after ourselves.
    defer {
        for *things {
            free(it.text);
            free(it.name);
        }
        array_free(things);
    }
    
    // We set up some IO Data for the `Thing` struct so that we get nicer syntax in the GON file, and more compact serialization.
    add_io_data(Thing, .{
        name_member = get_field(type_info(Thing), "name"),
        flags       = .SKIP_ELEMS_IF_EMPTY
    });
    
    
    // some other things we want to parse from the same file
    fruit_facts: Fruit_Facts;
    csv:         CSV;
    
    add_io_data(Fruit_Facts, .{
        flags = .ARRAY_INDEXED,
        enum_index_type = xx Fruits
    });
    
    add_io_data(type_of(fruit_facts[0]), .{
        flags = .AS_ARRAY,
    });
    
    add_io_data(CSV, .{
        parse_proc     = string_to_csv,
        serialize_proc = csv_to_string
    });
    
    
    // Once can also load the file manually and call parse_file() instead.
    // But this version is often nicer, because we pass along the file path to the parser for use in error logging.
    parser, ok := load_and_parse_file("test.gon");
    if !ok  return;
    defer deinit_parser(*parser);
    
    // This call will create a new data bindings between our internal `things` array and the GON DOM.
    // This process involves allocating space for everything in our `things` array, 
    // so if the call fails, one should remember to free anything that got allocated here.
    // Note that strings are copied when evaluating data bindings, and are not views onto the source file.
    // This means that for our program to be correct, we would need to free the `name` and `text` members of each element of `things`, as well as `things` itself.
    if !add_data_binding(*parser, things, "things") {
        log("Error: failed to add data binding to GON DOM.");
        return;
    }
    
    // add the remaining data bindings
    if !add_data_bindings(*parser,
        .{ csv,         "foo/csv" },
        .{ fruit_facts, "foo/bar/fruit_facts" },
    ) {
        log("Error: failed to add data bindings to GON DOM.");
        return;
    }
    
    // This call will walk over the DOM and evaluate the data bindings placed on each node.
    // After this procedure completes successfully, 
    if !process_data_bindings(*parser) {
        log("Error: failed to process data bindings.");
        return;
    }
    
    /*
        Alternatively to all of the above, we can do a nice little one-liner:
        
        ok := load_and_parse_file_with_data_bindings("test.gon", 
            .{ things, "foo/bar/other_things" }
            .{ string, "foo/baz_1" }
        );
    */
    
    // Setting print_style to use newlines, so the data is more legible, 
    // and we can more easily compare to the re-serialized GON output below.
    context.print_style.default_format_struct.use_newlines_if_long_form = true;
    context.print_style.default_format_struct.use_long_form_if_more_than_this_many_members = -1;
    
    print("Behold, the things we parsed:\nthings: %\n\nfruit_facts: %\n\ncsv: %\n\n", things, fruit_facts, csv);
    
    
    
    
    // The parser is also used for serialization.
    // We create a new instance here so that we can create a new DOM from scratch.
    init_parser(*parser, "");
    
    // Uncomment this line to see Vector3 serialized as a GON array instead of a GON object.
    // add_io_data(Vector3, .{ flags = .AS_ARRAY });
    
    // Like add_data_bindings, this procedure works recursively, 
    // generating DOM nodes for every single array element and member variable.
    insert_data_node(*parser, null, "things", things);
    insert_data_node(*parser, null, "csv", csv);
    insert_data_node(*parser, null, "fruit_facts", fruit_facts);
    
    // You may also serialize directly to a file with serialize_to_file().
    output:, ok = serialize_to_string(*parser);
    if !ok  return;
    defer free(output);
    
    print("Behold, the GON ouput we serialized:\n%\n", output);
}
