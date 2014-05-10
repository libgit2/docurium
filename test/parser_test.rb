require 'minitest/autorun'
require 'docurium'
require 'pp'

class TestParser < Minitest::Unit::TestCase

  def setup
    @parser = Docurium::DocParser.new
  end

  # e.g. parse('git2/refs.h')
  def parse(path, contents)
    @parser.parse_file(path, [[path, contents]])
  end

  def test_single_function

    name = 'function.h'
    contents = <<EOF
/**
* Do something
*
* More explanation of what we do
* 
* @param string a sequence of characters
* @return an integer value
*/
int some_function(char *string);
EOF

    actual = parse(name, contents)
    expected = [{:file => "function.h",
                  :line => 9,
                  :lineto => 9,
                  :tdef => nil,
                  :type => :function,
                  :name => 'some_function',
                  :body => 'int some_function(char *string);',
                  :description => ' Do something',
                  :comments => " More explanation of what we do\n\n ",
                  :sig => 'char *',
                  :args => [{
                              :name => 'string',
                              :type => 'char *',
                              :comment => 'a sequence of characters'
                            }],
                  :return => {
                    :type => 'int',
                    :comment => ' an integer value'
                  },
                  :decl => 'int some_function(char *string)',
                  :argline => 'char *string',
                }]

    assert_equal expected, actual
  end

  def test_single_multiline_function

    name = 'function.h'
    contents = <<EOF
#include <stdlib.h>
/**
* Do something
*
* More explanation of what we do
* 
* @param string a sequence of characters
* @return an integer value
*/
int some_function(
    char *string,
    size_t len);
EOF

    actual = parse(name, contents)
    expected = [{:file => "function.h",
                  :line => 10,
                  :lineto => 12,
                  :tdef => nil,
                  :type => :function,
                  :name => 'some_function',
                  :body => "int some_function(char *string, size_t len);",
                  :description => ' Do something',
                  :comments => " More explanation of what we do\n\n ",
                  :sig => 'char *::size_t',
                  :args => [{
                              :name => 'string',
                              :type => 'char *',
                              :comment => 'a sequence of characters'
                            },
                            {
                              :name => 'len',
                              :type => 'size_t',
                              :comment => nil
                            }],
                  :return => {
                    :type => 'int',
                    :comment => ' an integer value'
                  },
                  :decl => "int some_function(char *string, size_t len)",
                  :argline => "char *string, size_t len",
                }]

    assert_equal expected, actual
  end

  def test_parsing_with_extern

    name_a = 'common.h'
    contents_a = <<EOF
# define GIT_EXTERN(type) extern type
EOF

    name_b = 'function.h'
    contents_b = <<EOF
#include "common.h"

/**
* Awesomest API
*/
GIT_EXTERN(int) some_public_function(int val);
EOF

    actual = @parser.parse_file(name_b, [[name_a, contents_a], [name_b, contents_b]])
    # "Fix" the path so we remove the temp dir
    actual[0][:file] = File.split(actual[0][:file])[-1]

    expected = [{
                  :file => "function.h",
                  :line => 6,
                  :lineto => 6,
                  :tdef => nil,
                  :type => :function,
                  :name => "some_public_function",
                  :body => "int some_public_function(int val);",
                  :description => " Awesomest API",
                  :comments => "",
                  :sig => "int",
                  :args => [{
                              :name=>"val",
                              :type=>"int",
                              :comment=>nil
                            }],
                  :return => {
                    :type=>"int",
                    :comment=>nil
                  },
                  :decl =>"int some_public_function(int val)",
                  :argline =>"int val"
                }]

    assert_equal expected, actual

  end

  def test_parse_struct

    name = 'struct.h'

    contents = <<EOF
/**
* Foo to the bar
*/
typedef struct {
    int val;
    char *name;
} git_foo;
EOF

    actual = parse(name, contents)

    expected = [{
                  :file => "struct.h",
                  :line => 4,
                  :lineto => 7,
                  :tdef => :typedef,
                  :type => :struct,
                  :name => "git_foo",
                  :underlying_type => 'struct git_foo',
                  :description => " Foo to the bar",
                  :comments => "",
                  :fields => [
                              {
                                :type => "int",
                                :name => "val",
                                :comments => "",
                              },
                              {
                                :type => "char *",
                                :name => "name",
                                :comments => "",
                              }
                             ],
                  :decl => ["int val", "char * name"],
                  :block => "int val\nchar * name"
                }]

    assert_equal expected, actual

  end

  def test_parse_struct_with_field_docs

    name = 'struct.h'

    contents = <<EOF
/**
* Foo to the bar
*/
typedef struct {
/**
* This stores a value
*/
    int val;
/**
* And this stores its name
*
* Which should be pretty descriptive
*/
    char *name;
} git_foo;
EOF

    actual = parse(name, contents)
    expected = [{
                  :file => "struct.h",
                  :line => 4,
                  :lineto => 15,
                  :tdef => :typedef,
                  :type => :struct,
                  :name => "git_foo",
                  :underlying_type => 'struct git_foo',
                  :description => " Foo to the bar",
                  :comments => "",
                  :fields => [
                              {
                                :type => "int",
                                :name => "val",
                                :comments => " This stores a value",
                              },
                              {
                                :type => "char *",
                                :name => "name",
                                :comments => " And this stores its name\n\n Which should be pretty descriptive",
                              }
                             ],
                  :decl => ["int val", "char * name"],
                  :block => "int val\nchar * name"
                }]

    assert_equal expected, actual

  end

  def test_parse_enum

    name = 'enum.h'
    contents = <<EOF
/**
* Magical enum of power
*/
typedef enum {
FF  = 0,
/** Do not allow fast-forwards */
NO_FF = 1 << 2
} git_merge_action;
EOF

    actual = parse(name, contents)
    expected = [{
                  :file => 'enum.h',
                  :line => 4,
                  :lineto => 8,
                  :tdef => :typedef,
                  :type => :enum,
                  :name => "git_merge_action",
                  :underlying_type => 'enum git_merge_action',
                  :description => " Magical enum of power",
                  :comments => "",
                  :fields => [{
                                :type => "int",
                                :name => "FF",
                                :comments => "",
                                :value => 0,
                              },
                              {
                                :type => "int",
                                :name => "NO_FF",
                                :comments => " Do not allow fast-forwards ",
                                :value => 4,
                              }],
                  :block => "FF\nNO_FF",
                  :decl => ["FF", "NO_FF"]
                }]

    assert_equal expected, actual

  end

  def test_parse_define

    name = 'define.h'
    contents = <<EOF
/**
* Path separator
*/
#define PATH_SEPARATOR '/'
EOF

    actual = parse(name, contents)

    #Clang won't let us do comments on defines :("
    assert_equal [], actual

  end

  def test_type_reference

    name = 'typeref.h'
    contents = <<EOF
/**
* My very own type
*/
typedef int my_type;
EOF

    actual = parse(name, contents)
    expected = [{
                  :file => "typeref.h",
                  :line => 4,
                  :lineto => 4,
                  :tdef => :typedef,
                  :name => "my_type",
                  :underlying_type => "int"
                }]

    assert_equal actual, expected

    name = 'typeref.h'
    contents = <<EOF
/**
* My very own type
*/
typedef struct my_type my_type;
EOF

    actual = parse(name, contents)
    expected = [{
                  :file => "typeref.h",
                  :line => 4,
                  :lineto => 4,
                  :tdef => :typedef,
                  :name => "my_type",
                  :underlying_type => "struct my_type",
                  :decl => 'my_type',
                }]

    assert_equal actual, expected


  end

end
