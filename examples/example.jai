#import "Basic";
#import "File";
#import "Math";
#import "Reflection";

#import "GON";

Thing :: struct {
    name:       string;
    text:       string;
    numbers:    [5] int;
    position:   Vector3;
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
    // This array and everything within it will get filled in by the parser.
    // (You can also change this to a resizable array, and it will work the same.)
    things: [] Thing;
    
    // For the sake of setting a good example, let's clean up after ourselves.
    defer {
        for *things {
            free(it.text);
            free(it.name);
        }
        array_free(things);
    }
    
    // We set up some IO Data for the `Thing` struct so that we get nicer syntax in the GON file, and more compact serialization.
    // The name_member 
    add_io_data(Thing, .{
        name_member = get_field(type_info(Thing), "name"),
        flags       = .SKIP_ELEMS_IF_EMPTY
    });
    
    // Once can also load the file manually and call parse_file() instead.
    // But this version is often nicer, because we pass along the file path to the parser for use in error logging.
    parser, ok := load_and_parse_file("test.gon");
    if !ok return;
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
    
    print("Behold, the things we parsed:\n%\n", things);
    
    // The parser is also used for serialization.
    // We create a new instance here so that we can create a new DOM from scratch.
    init_parser(*parser, "");
    
    // Like add_data_bindings, this procedure works recursively, 
    // generating DOM nodes for every single array element and member variable.
    insert_data_node(*parser, null, "things", things);
    
    // You may also serialize directly to a file with serialize_to_file().
    output:, ok = serialize_to_string(*parser);
    defer free(output);
    if ok  print("%\n", output);
}
