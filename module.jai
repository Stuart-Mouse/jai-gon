/*
  Copyright (C) 2025 Noah Wilson
  This software is provided 'as-is', without any express or implied
  warranty.  In no event will the authors be held liable for any damages
  arising from the use of this software.

  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, and to alter it and redistribute it
  freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not
     claim that you wrote the original software. If you use this software
     in a product, an acknowledgment in the product documentation would be
     appreciated but is not required.
  2. Altered source versions must be plainly marked as such, and must not be
     misrepresented as being the original software.
  3. This notice may not be removed or altered from any source distribution.
*/

#scope_module

#import "Basic";
#import "Reflection";
#import "String";
#import "Flat_Pool";
#import "File";
#import "Math";

// I have no idea why next_power_of_two is #scope_export...
using,except(next_power_of_two) Hash_Table :: #import "Hash_Table";

Convert :: #import "Convert";
#import "Utils";

#load "dom.jai";
#load "parse.jai";
#load "serialize.jai";
#load "lexer.jai";
#load "io_data.jai";
