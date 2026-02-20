/*
    Jai Data Marshaller      ( written by u0 )
    
    Feel free to use this code in part or whole however you wish, though I do ask that you give credit if you use this module or a substantial portion of this code in your project.
    
    I want to say a special thanks to Tyler Glaiel for creating GON. 
    Implementing a GON model has been my first real project in just about every language I know well, and the experience has taught me a lot each time.
    This module started its life as a humble GON model and serializer, and now it's grown up to do a lot more stuff.
    
    TODO: Write a little bit of documentation here about the features of the module and how to use it.
    
    
    
    
*/

// TODO: once the compiler bug that generate dumb warnings is fixed, it woudl be nice to reinstate this module_parameters stuff.
//       But for now it is too much hassle, so instead users can just manaully exclude the languages they don't care about here by commenting out the #loads.

#load "languages/JSON/submodule.jai";
#load "languages/XML/submodule.jai";

// #module_parameters ()(LANGUAGES: [] string);

// #insert #run,stallable -> string {
//     builder: String_Builder;
//     for LANGUAGES {
//         find_submodule_and_append(*builder, "languages", it);
//     }
//     result := builder_to_string(*builder,, temp);
//     return result;
// };

// find_submodule_and_append :: (builder: *String_Builder, submodule_directory: string, submodule_name: string, loc := #caller_location) #compile_time {
//     module_directory := path_strip_filename(loc.fully_pathed_filename);
    
//     // try importing single-file submodule
//     submodule_file_path := tprint("%/%/%.jai", module_directory, submodule_directory, submodule_name);
//     if file_exists(submodule_file_path) {
//         print(builder, "% :: #import,file \"%\";\n", submodule_name, submodule_file_path);
//         return;
//     }
    
//     // try importing folder-based submodule
//     submodule_file_path = tprint("%/%/%/submodule.jai", module_directory, submodule_directory, submodule_name);
//     if file_exists(submodule_file_path) {
//         print(builder, "% :: #import,file \"%\";\n", submodule_name, submodule_file_path);
//         return;
//     }
    
//     assert(false, "Unable to locate submodule '%' in '%/%'.", submodule_name, module_directory, submodule_directory);
// }


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

// TODO: add version of load_and_parse_file that infers the language automatically based on the file extension.
//       we will need to have some global lookup table to associate a file extension with a particular file type
//       user will need to register the language file associations with language ID and some default config, since maybe the file extension will indicate to use some different language config, e.g. JSON vs GON

parse_file :: (model: *Data_Model, file: string, file_path_for_logging := "") -> bool {
    if !model.language.parse {
        log("Data Model Error: language does not implement parse()!"); 
        return false;
    }
    if !model.language.parse(model, file, file_path_for_logging, null) {
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
        if !model.language.serialize(builder, model, it)
            return false;
    
    return true;
}


#scope_module

#import "Basic";
#import "String";
#import "File";
#import "File_Utilities";
#import "Math";
#import "Flat_Pool";
#import "Unicode";

// I have no idea why next_power_of_two is #scope_export...
using,except(next_power_of_two) Hash_Table :: #import "Hash_Table";

Reflection :: #import "Reflection";
#import "Reflect";

#load "data_model.jai";
#load "language.jai";
#load "io_data.jai";
#load "path.jai";
#load "log.jai";
#load "utils.jai";

