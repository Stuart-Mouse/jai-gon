
// TODO: probably put some kind of info in here or somethin

#scope_module

#import "Basic";
#import "Reflection";
#import "String";
#import "Flat_Pool";

// I have no idea next_power_of_two is #scope_export...
using,except(next_power_of_two) Hash_Table :: #import "Hash_Table";

#import "Data_Packer";
#import "Utils";

#load "dom.jai";
#load "parse.jai";
#load "serialize.jai";
#load "lexer.jai";
#load "io_data.jai";
