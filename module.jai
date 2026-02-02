/*
    Jai Data Marshaller      ( written by u0 )
    
    Feel free to use this code in part or whole however you wish, though I do ask that you give credit if you use this module or a substantial portion of this code in your project.
    
    I want to say a special thanks to Tyler Glaiel for creating GON. 
    Implementing a GON model has been my first real project in just about every language I know well, and the experience has taught me a lot each time.
    This module started its life as a humble GON model and serializer, and now it's grown up to do a lot more stuff.
    
    TODO: Write a little bit of documentation here about the features of the model and how to use it.
    
    
    
    
*/


#module_parameters ()(LANGUAGES: [] string, TYPES: [] string = .[]);

// ========== Parsing ==========

// TODO: pass parameter for language to these convenience functions

// load_and_parse_file_with_bindings :: (file_path: string, bindings: ..Binding_With_Path) -> bool {
//     model: Data_Model;
//     init_data_model(*model);
//     defer deinit_data_model(*model);
    
//     model.language = GON_get_langauge();
    
//     file, ok := read_entire_file(file_path,, get_allocator(*model.memory_pool));
//     if !ok  return false;
    
//     if !model.language.parse {
//         log("Data Model Error: language does not implement parse()!"); 
//         return false;
//     }
//     if !model.language.parse()
    
//     ok = add_data_bindings(*model, ..bindings);
//     if !ok  return false;
    
//     ok = process_data_bindings(*model);
//     if !ok  return false;
    
//     return true;
// }

// // NOTE: user does not need to worry about freeing file, since we allocate it in the model's pool.
// load_and_parse_file :: (file_path: string) -> Data_Model, bool {
//     model: Data_Model;
//     init_model(*model, "");
    
//     ok: bool;
//     defer if !ok  deinit_model(*model);
    
//     file:, ok = read_entire_file(file_path,, get_pool_allocator(*model.node_pool));
//     if !ok  return .{}, false;
    
//     init_lexer(*model.lexer, file, file_path);
    
//     ok = construct_dom(*model);
//     if !ok  return .{}, false;
    
//     return model, ok;
// }

parse_file :: (model: *Data_Model, file: string, file_path_for_logging := "") -> bool {
    if !model.language.parse {
        log("Data Model Error: language does not implement parse()!"); 
        return false;
    }
    if !model.language.parse(model, file, file_path_for_logging) {
        log("Data Model Error: Failed to parse file: %", file_path_for_logging);
        return false;
    }
    return true;
}


// ========== Serialization ==========

serialize_to_string :: (using model: *Data_Model) -> bool, string {
    builder: String_Builder;
    if !serialize_to_builder(model, *builder) {
        free_buffers(*builder);
        return false, "";
    }
    return true, builder_to_string(*builder);
}

serialize_to_file :: (using model: *Data_Model, file_path: string) -> bool {
    builder: String_Builder;
    if !serialize_to_builder(model, *builder) {
        free_buffers(*builder);
        return false;
    }
    return write_entire_file(file_path, builder_to_string(*builder));
}

serialize_to_builder :: (using model: *Data_Model, builder: *String_Builder) -> bool {
    if model.root == null  return false;
    
    for model.root.children 
        if !model.language.serialize_node(builder, model, it)
            return false;
    
    return true;
}


#scope_module

#import "Basic";
#import "String";
#import "File";
#import "Math";
#import "Flat_Pool";

// I have no idea why next_power_of_two is #scope_export...
using,except(next_power_of_two) Hash_Table :: #import "Hash_Table";

Convert :: #import "Convert";
#import "Utils";

#load "data_model.jai";
#load "language.jai";
#load "io_data.jai";
#load "path.jai";
#load "log.jai";

// TODO: Check if files are actually present, check for `languages/<name>.jai` as alternative to folder with submodule.jai
//       This will require that we somehow figre out the path of this current module...
#insert -> string {
    FORMAT_STRING := "#load \"languages/%/submodule.jai\";";
    builder: String_Builder;
    for LANGUAGES {
        print(*builder, FORMAT_STRING, it);
    }
    return builder_to_string(*builder,, temp);
}

#insert -> string {
    FORMAT_STRING := "#load \"types/%/submodule.jai\";";
    builder: String_Builder;
    for TYPES {
        print(*builder, FORMAT_STRING, it);
    }
    return builder_to_string(*builder,, temp);
}

