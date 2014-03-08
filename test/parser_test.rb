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

    skip("Let's go one at a time")

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
int some_function(
    char *string,
    size_t len);
EOF

    actual = @parser.parse_file(name, [[name, contents]])
    expected = [{:file => "function.h",
                  :line => 9,
                  :decl => "int some_function(\n    char *string,\n    size_t len)",
                  :body => "int some_function(\n    char *string,\n    size_t len);",
                  :type => :function,
                  :args => [{
                              :name => 'string',
                              :type => 'char *',
                              :comment => 'a sequence of characters'
                            },
                            {
                              :name => 'len',
                              :type => 'size_t',
                            }],
                  :return => {
                    :type => 'int',
                    :comment => 'an integer value'
                  },
                  :argline => "char *string,\n    size_t len",
                  :sig => 'char *::size_t',
                  :description => 'Do something',
                  :lineto => 11,
                  :comments => "More explanation of what we do\n",
                  :name => 'some_function'}]

    assert_equal expected, actual
  end

end
