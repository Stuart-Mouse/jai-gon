/*
    NOTE: This is not a conformat XML implementation by any means, this is just being done as a proof-of-concept for the time being so that the overall structure of the module can be developed.
    
    
*/


XML_get_language :: (config := XML_Config.{}) -> Language {
    ctx := New(XML_Context);
    ctx.config = config;
    
    return .{
        name              = "XML",
        id                = XML_LANGUAGE_ID,
        language_context  = ctx,
        parse             = XML_parse,
        serialize_node    = XML_serialize_node,
        deinit            = XML_deinit_language,
    };
}

XML_deinit_language :: (model: *Data_Model) {
    ctx := model.language.language_context.(*XML_Context);
    free(ctx);
}

XML_Context :: struct {
    using config: XML_Config;
    
    lexer:  XML_Lexer;
}

XML_Config :: struct {
    xml_flags: Flags;
    Flags :: enum_flags {
        NONE :: 0;
    }
    
    // TODO: maybe handle indentation differently, pass as parameter to serialize proc or something...
    indentation_string := "    ";
}

#scope_module

XML_LANGUAGE_ID :: "XML";

XML_parse :: (model: *Data_Model, file: string, file_path_for_logging := "", into: *Data_Model.Node = null) -> bool {
    using xml_context := model.language.language_context.(*XML_Context);
    
    init_lexer(*lexer, lexer_config, file, file_path_for_logging);
    
    
    
    
    
    return true;
}

/*

try_parse_tag
    <name (attributes)*> content </name>

try_parse_attribute
    name = "value"


*/

