#import "Basic";
#import "File";
#import "Math";
#import "Reflection";
#import "String";

#import "GON";

/*
    Apologies up front for this exmple file being a bit of a scattered mess! 
    Hopefully it's still legible enough for you to understand.
    I had it more cleanly divided into sectionsbefore, but then I wanted to add the serialization sectino and had to get all the things we loaded back into scope...
    
    In any case, I don't demo every single little thing the parser can do, 
    but the broad strokes are there and I think most of the code is relatively 
    organized so that you can find what you're looking for in the source.
    
*/

main :: () {
    write_string("===== Example 1: the basics =====\n");
    {
        // Suppose we have the following GON file:
        file :: #string END
        my_int  5
        foo {
            my_float   3.5
            my_string  "this is a string"
        }
        END
        
        // First, we parse the file. This will construct the DOM so that we can create data bindings to the data in the file.
        // (A 'file path' can be provided as the second parameter for use in error logging.)
        parser, ok := parse_file(file, "Example 1");
        if !ok  return;
        
        // Always remember to deinit the parser so that the DOM gets freed.
        defer deinit_parser(*parser);
        
        // Now we want to extract some information from this file into the following variables:
        my_int:     int;
        my_float:   float;
        my_string:  string;
        
        // So we create data bindings with the variables and the path to the data in the file:
        ok = add_data_bindings(*parser, 
            .{ my_int,    "my_int"        },
            .{ my_float,  "foo/my_float"  },
            .{ my_string, "foo/my_string" },
        );
        if !ok  return;
        
        // After processing our data bindings, the variables we bound will have their values filled in.
        ok = process_data_bindings(*parser);
        if !ok  return;
        
        
        print("my_int:    %\n", my_int);
        print("my_float:  %\n", my_float);
        print("my_string: \"%\"\n", my_string);
    }
    write_string("\n\n");

    
    write_string("===== Example 2: structs and arrays =====\n");

    // Now instead of single variables, we have a struct with lots of stuff in it:    
    
    Thing :: struct {
        name:       string;
        text:       string;
        numbers:    [5] int;
        position:   Vector3;
        flags:      Flags;
        
        Flags :: enum_flags { FIRST; SECOND; THIRD; }
    }
    
    
    // This array and everything within it will get filled in by the parser.
    // (You can also change this to a resizable array, and it will work the same.)
    things:  [] Thing;
    
    // For the sake of setting a good example, let's clean up after ourselves.
    // Note that strings and arrays which get set by the GON parser will need to be freed individually unless you pushed some special allocator.
    defer {
        for *things {
            free(it.text);
            free(it.name);
        }
        array_free(things);
    }
    
    // We set up some IO Data for the `Thing` struct so that we get nicer syntax in the GON file, and more compact serialization.
    // Assigning a name member to the `Thing` struct will tell the parser to assign the name of the GON object to which the struct is bound to this particular member.
    // The SKIP_ELEMS_IF_EMPTY flag will prevent serialization of any struct members which are zero-valued.
    add_io_data(Thing, .{
        name_member = get_field(type_info(Thing), "name"),
        flags       = .SKIP_ELEMS_IF_EMPTY
    });
    
    
    /*
        A slight aside:
    
        Structs can bind to either GON objects or arrays.
        If bound to an object, we use the name of each field in the object to make bindings to the struct's members.
        If bound to an array, we just bind to the fields of the struct in order.
        You can think of this like the difference between the two types of struct literals in Jai.
        
        Similarly, arrays can bind to both GON objects and arrays, but the rules are a bit more strict. 
        An array can only be bound to a GON object if it has some IO_Data defined to indicate that the array is indexed, 
            or if the element type is a struct with some name member defined in its IO_Data.
        This is due to the fact that, lexically speaking, GON arrays are always a simple series of values, while GON objects consist of name/value pairs.
        So whether or not you use an object or array in GON depends solely on whether or not the fields within the aggregate type will be named.
    */
    
    {
        // One can also load the file manually and call parse_file() instead.
        // But load_and_parse_file is often nicer, because we automatically pass along the file path to the parser for use in error logging.
        // Not to mention, the loaded file gets allocated in same pool as the DOM nodes, so you can free everything all at once in deinit_parser().
        parser, ok := load_and_parse_file("example.gon");
        if !ok  return;
        defer deinit_parser(*parser);
        
        if !add_data_binding(*parser, things, "things")  return;
        
        if !process_data_bindings(*parser)  return;
    }
    
    // Setting print_style to use newlines, so the data is more legible, 
    // and we can more easily compare to the re-serialized GON output below.
    context.print_style.default_format_struct.use_newlines_if_long_form = true;
    context.print_style.default_format_struct.use_long_form_if_more_than_this_many_members = -1;
    
    print("Behold, the things we parsed:\n%\n", things);
    
    write_string("\n\n");
    
    
    write_string("===== Example 3: indexed arrays and custom parsing =====\n");
    
    /*
        Indexed and enumerated arrays can be very helpful for lookup tables and the like.
        In this example we have some enum `Fruits` which indexes a lookup table `fruit_facts`.
    */
    Fruits :: enum {
        APPLE;
        PEAR;
        BANANA;
        STRAWBERRY;
        KIWI;
        
        _COUNT;
    }
    
    fruit_facts: [Fruits._COUNT] struct {
        nutrition:    int;
        flavor:       int;
        description:  string;
    };
    
    add_io_data(type_of(fruit_facts), .{
        flags = .ARRAY_INDEXED,
        enum_index_type = xx Fruits
    });
    
    // For compactness, serialize the elements in GON array format.
    add_io_data(type_of(fruit_facts[0]), .{ flags = .AS_ARRAY, });
    
        
        
    /*
        Custom parsing and serialization procs.
        This is a bit of a contrived example, but I wanted to keep it simple.
        A more realistic example may be something like a DateTime value that you want to have in a human-readable string in the GON file, but is stored internally as Apollo_Time.
        You can just plug in the code to adapt it to/from a string and then you don't have to worry about post-processing your data after loading it in from a file.
    */
    CSV :: [] string;
    
    string_to_csv :: (val: Any, str: string) -> bool {
        assert(val.type == xx CSV);
        csv := val.value_pointer.(*CSV);
        csv.* = split(str, ",".(u8));
        
        // We must copy all of these individual strings, since the underlying file will get freed.
        for *(csv.*)  it.* = copy_string(it.*);
        return true;
    }
    
    csv_to_string :: (val: Any) -> string, bool {
        assert(val.type == xx CSV);
        csv := val.value_pointer.(*CSV);
        
        // We allocate the output string with temp since GON won't free it for us.
        str := join(..csv.*, separator = ",",, temp);
        return str, true;
    }
    
    csv: CSV;
    
    add_io_data(CSV, .{
        parse_proc     = string_to_csv,
        serialize_proc = csv_to_string
    });
    
    
    
    // Cute little one-liner! (Using the same file as the previous example.)
    // Notice in example.gon that 
    ok := load_and_parse_file_with_bindings("example.gon", 
        .{ csv,         "foo/csv" },
        .{ fruit_facts, "foo/bar/fruit_facts" },
    );
    if !ok  return;
    
    
    print("fruit_facts:\n%\n\n", fruit_facts);
    print("csv:\n%\n", csv);
    
    write_string("\n\n");
    
    
    {
        write_string("===== Example 4: Serialization =====\n");
        
        // The parser is also used for serialization.
        parser: Parser;
        init_parser(*parser, "");
        
        // Uncomment this line to see Vector3 serialized as a GON array instead of a GON object.
        // add_io_data(Vector3, .{ flags = .AS_ARRAY });
        
        // Like add_data_bindings, this procedure works recursively, 
        // generating DOM nodes for every single array element and member variable.
        insert_data_node(*parser, null, "things", things);
        insert_data_node(*parser, null, "foo/bar/fruit_facts", fruit_facts);
        insert_data_node(*parser, null, "foo/csv", csv);
        
        output, ok := serialize_to_string(*parser);
        if !ok  return;
        defer free(output);
        
        print("Behold, the GON ouput we serialized:\n%\n", output);
        
        // Uncomment this line to output to a file:
        // serialize_to_file(*parser, "example_output.gon");
        write_string("\n\n");
    }
}
