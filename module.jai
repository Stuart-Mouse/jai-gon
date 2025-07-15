
// TODO: probably put some kind of info in here or somethin

#scope_module

#module_parameters()(USING_FLAT_POOL := false);

#import "Basic";
#import "Reflection";
#import "String";
#import "File";
#import "Math";

#if USING_FLAT_POOL {
    #import "Flat_Pool";
} else {
    #import "Pool";
}

// I have no idea why next_power_of_two is #scope_export...
using,except(next_power_of_two) Hash_Table :: #import "Hash_Table";


Convert :: #import "Convert";
#import "Utils";

#load "dom.jai";
#load "parse.jai";
#load "serialize.jai";
#load "lexer.jai";
#load "io_data.jai";
