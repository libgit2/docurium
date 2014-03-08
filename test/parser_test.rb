require 'minitest/autorun'
require 'docurium'
require 'pp'

class TestParser < Minitest::Unit::TestCase

  def setup
    @parser = Docurium::DocParser.new
  end

  # e.g. parse('git2/refs.h')
  def parse(path)
    realpath = File.dirname(__FILE__) + '/fixtures/' + path

    parser = Docurium::DocParser.new
    parser.parse_file(path, [[path, File.read(realpath)]])
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

    actual = @parser.parse_file(name, [[name, contents]])
    expected = [{:file => "function.h",
                  :line => 9,
                  :lineto => 9,
                  :tdef => nil,
                  :type => :function,
                  :name => 'some_function',
                  :body => 'int some_function(char *string);',
                  :description => ' Do something',
                  :comments => " Do something\n More explanation of what we do\n ",
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

    actual = @parser.parse_file(name, [[name, contents]])
    expected = [{:file => "function.h",
                  :line => 10,
                  :lineto => 12,
                  :tdef => nil,
                  :type => :function,
                  :name => 'some_function',
                  :body => "int some_function(char *string, size_t len);",
                  :description => ' Do something',
                  :comments => " Do something\n More explanation of what we do\n ",
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
                  :comments => " Awesomest API",
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

end
