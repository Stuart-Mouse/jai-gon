#import "Basic";
#import "String";
GON :: #import "GON";

/*
  The most basic feature of this parser is the data binding.
  This represents a relationship between some data internally in your program and a field in the GON file being parsed.
  With data bindings, you can very quickly load all kinds of information into your program, 
    without needing to use callbacks or write a single line of code to traverse a DOM.
  
  Throughout this file, I will introduce the various type of data bindings that one can perform 
    and the standard ways in which one may express that data in a GON file.
*/

/*
  First, lets just create a few basic data types that should be familiar to any programmer.
  Using these basic data types, we'll create some more complex structs with nested types.

  For simple single-valued type such as int, string, and enum types, one can simply create a direct data binding
    to a GON field by specifying the name of the field and providing the variable to which one wants to store the value back to.
  When this variable is specified, it is converted to an "Any", which is built-in type in Jai which contains a pointer 
    to the data of some variable as well as a pointer to the type_info struct for the type of the variable.
  Using the runtime type info of Jai, we can convert, type-check, and safely store a string value to any of these basic types.
*/

/*
  Enums values can be represented in GON by the names of the values.
*/
Month :: enum #specified {
  JANUARY   :: 1;
  FEBRUARY  :: 2;
  MARCH     :: 3;
  APRIL     :: 4;
  MAY       :: 5;
  JUNE      :: 6;
  JULY      :: 7;
  AUGUST    :: 8;
  SEPTEMBER :: 9;
  OCTOBER   :: 10;
  NOVEMBER  :: 11;
  DECEMBER  :: 12;
}

// This enum does not have integer values explicitly defined for its values, 
//   but this is fine because we parse enum values by name. 
HairColor :: enum {
  BLONDE;
  BROWN;
  BLACK;
  WHITE;
  RED;
}

/*
  Structs are multi-valued types, so they can be represented in GON as either an object or an array.
  When a struct is defined as a GON object, the fields within the object are bound to the members of the struct implicitly by name.
  So if our struct has a member called "day", like in the example below, then if the parser finds a field called "day"
    in an object bound to a DateOfBirth struct, then it will automatically bind the field to the corresponding struct member.
  Alternatively, if our struct is bound to a GON array, then we can just give the values of each of the fields in order. 
  We will do this below when we provide the values for dates of birth in our sample GON file. 
*/
DateOfBirth :: struct @gon_serialize_as_array { 
  month : Month;
  day   : int;
  year  : int;
} 

/* 
  Not all enums are the same however!
  enum_flags can have multiple values, so they can be represented in GON as an array type 
    in which each string in the array is a flag that will be OR'd in to the final value.
*/
Disability :: enum_flags {
  BLIND;
  MUTE;
  DEAF;
  LAME;
}

/* 
  A slightly more complex structure, containing all of the previously defined types.
  The @gon_name note can be placed on a struct member to specify that this member 
    will act as the name field of a GON object during parsing and serialization.
  Generally, I would recommend that this only ever be bound to a string.
  In theory, you may bind this to any basic single-value type which can be represented by a string.
*/
Person :: struct {
  name          : string;      @gon_name
  age           : int;
  date_of_birth : DateOfBirth;
  hair_color    : HairColor;
  disability    : Disability;
}

/*
  This struct contains a resizeable array of our Person struct.
  An array of a struct is a relativley complicted data type for a parser to handle automatically, 
    but thanks to the runtime type info of Jai, we can do this easily.
*/
Town :: struct {
  name   : string;      @gon_name
  people : [..] Person; @gon_serialize_as_object
}

/*
  In lieu of loading from a file (and for the purposes of demonstration), 
    we will use a string literal for the GON data we're parsing.
  The parser will operate on any string that you give it, so in theory 
    you could get this string from user input, over the internet, or from any other source.

  In addition to our town, we will create a GON object with a couple fields inside it that 
    we want to create data bindings to, but without making a direct data binding to the object itself.
*/

GON_STRING := #string DONE
object {
  string "This is a string."
  numbers [ 1, 2.2, 3, 4.4, 5 ]
}

town {
  name Springfield
  people {
    "Tommy" {
      age 13
      hair_color RED
      date_of_birth [ MARCH 7 2010 ]    # We can provide struct values in order using the GON array syntax.
    }
    "Johnny" {
      age 35
      hair_color BLONDE
      date_of_birth [ FEBRUARY 2 1988 ]
    }
    "Jimmy" {
      age 92
      hair_color BROWN
      disability [ BLIND, DEAF ]        # We can provide multiple enum_flags values using the GON array syntax.
      date_of_birth [ AUGUST 15 1931 ]
    }
  }
}
DONE

main :: () {
  /*
    First, we create variables that we will store our data back to as we parse our GON file.
    Try changing the size of the numbers array or adding items to the GON array it is bound to.
    If a fixed size array is too small for the data we attempt to add, then we will get an error. 
  */
  town    : Town;
  message : string;
  numbers : [5] float; 

  /*
    Before we begin parsing, we need to create a parse context.
    This structure represents the state of the parser and it is passed as the first parameter to all parsing procedures.
    You must always initialize the file member and provide some data bindings or callbacks (otherwise, nothing will happen during parsing).

    For out simple example, we will only provide a single data binding relating the "town" GON object in the root of our file
      to the town struct we declared above.
    In the parse context, data_bindings is an array view, so please ensure that the underlying data lives for at least as long as the parse context. 
    Below, we are initializing the data bindings using array and struct literals, but one could determine what information 
      they want to bind dynamically. 
  */
  parse_context : GON.ParseContext = .{
    file = GON_STRING,
    data_bindings = .[
      .{ 
        field_address = .["town"],
        data_binding  = town        // This is an implicit cast to Any.
      },
      /*
        The field address provided is an array view of strings, 
          so if we want to create a data binding to a nested field,
          then we can give the names of each nested field like so:
      */
      .{ 
        field_address = .["object", "string"],
        data_binding  = message                 // The name of our variable does not need to match the name of the field we bind to.
      },
      .{ 
        field_address = .["object", "numbers"],
        data_binding  = numbers
      },
    ],
  };

  success := GON.parse_file(*parse_context);

  if !success return;

  /*
    Here we'll just print the values of these variables using Jai's default printing 
      in order to show that the data was loaded properly.
  */
  print("message: %\n", message);
  print("numbers: %\n", numbers);
  print("town: %\n", town);
}

