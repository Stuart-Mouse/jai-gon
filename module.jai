/*
    The Jai GON Parser

    This module is provided with no warranty or guarantees whatsoever. 
    I don't know what all the proper legal jargon is to include here, and I have not yet selected a proper license for the code. 
    For now, do whatever you wish with the code, so long as it's good. And make sure to link back to this original project.
*/


/*
    'parser' gets exported to caller, not sure if I like this or not, since it then exists outside macro, 
    and I really only want it scoped so that inserted code can see it, like how a for_expansion works..
    I would also like to be able to have the LS and GON procedures be usable without qualified names here...
*/
load_and_parse_file :: (path: string, code: Code) -> bool #expand {
    file, file_ok := read_entire_file(path);
    if !file_ok {
        log("Unable to open gon file '%'!", path);
        return false;
    }
    defer free(file);
    
    `parser, parser_ok := parse_file_to_dom(file, path);
    defer deinit_parser(*parser);
    if !parser_ok {
        log("Unable to parse gon file '%'!", path);
        log(format_error(parser.error)); 
        return false;
    }
    
    #insert code;
    
    if !process_data_bindings(*parser)  {
        log("Failed to process data bindings for gon file '%'!", path);
        log(format_error(parser.error)); 
        return false;
    }
    
    return true;
}


#load "dom.jai";
#load "parse.jai";
#load "serialize.jai";
#load "io_data.jai";

#scope_module

#import "Basic";
#import "File";
#import "Reflection";
#import "String";
#import "Flat_Pool";
using,except(next_power_of_two) Hash_Table :: #import "Hash_Table";

#import "Utils";
#import "Data_Packer";
using LS :: #import "Lead_Sheets";


coerce_small_any :: inline (dst_type: Type, src: Small_Any) -> (Small_Any, bool) {
    value, ok := coerce_small_any(type_info(dst_type), src);
    return value, ok;
}

coerce_small_any :: (dst_type: *Type_Info, src: Small_Any) -> (Small_Any, bool) {
    if is_numeric_type(dst_type) && is_numeric_type(src.type) {
        dst := Small_Any.{ type = dst_type };
        remap_data(to_any(*dst), to_any(*src));
        return dst, true;
    }
    return .{}, false;
}

