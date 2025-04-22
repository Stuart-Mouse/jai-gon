#import "Basic"()(MEMORY_DEBUGGER=true);
#import "File";
#import "Hash_Table";
#import "GON"()();
#import "Lead_Sheets"()(DEBUG=true);

Thing :: struct {
    name     : string;
    numbers  : [5] int;
    fraction : float;
    text     : string;
}

Flags :: enum_flags {
    first;
    second;
    third;
}

main :: () {
    // UA :: #import "Unmapping_Allocator";
    // context.allocator = UA.get_unmapping_allocator();
    
    {
        things: [..] Thing;
        defer {
            for *things {
                // free(it.text);
                free(it.name);
            }
            array_free(things);
        }
        flags: Flags;

        add_io_data(Thing, .{
            name_member = get_field(type_info(Thing), "name"),
        });

        file, ok := read_entire_file("test.gon");
        defer free(file);
        if !ok return;

        parser:, ok = parse_file_to_dom(file);
        defer deinit_parser(*parser);
        if !ok return;

        add_data_binding_to_dom(*parser, things, "things");
        add_data_binding_to_dom(*parser, flags, "flags");

        if !process_data_bindings(*parser) {
            log(format_error(parser.error));
            return;
        }
        
        // SERIALIZATION TEST
        // insert_data_node(*parser, "things", things);
        output:, ok = serialize_to_string(*parser);
        defer free(output);
        if ok  print("%\n", output);

        print("%\n", things);
        print("%\n", flags);
    }

    report_memory_leaks();
}

