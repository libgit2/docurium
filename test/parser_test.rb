require 'minitest/autorun'
require 'docurium'

class TestParser < Minitest::Unit::TestCase

  def setup
    @parser = Docurium::CParser.new
  end

  # e.g. parse('git2/refs.h')
  def parse(path)
    realpath = File.dirname(__FILE__) + '/fixtures/' + path

    parser = Docurium::CParser.new
    parser.parse_text(path, File.read(realpath))
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

    raw_comments = <<EOF
Do something

More explanation of what we do

@param string a sequence of characters
@return an integer value
EOF

    actual = @parser.parse_text(name, contents)
    expected = [{:file => "function.h",
                  :line => 9,
                  :body => 'int some_function(char *string);',
                  :rawComments => raw_comments.strip,
                  :type => :function,
                  :args => [{
                              :name => 'string',
                              :type => 'char *',
                              :comment => 'a sequence of characters'
                            }],
                  :return => {
                    :type => 'int',
                    :comment => 'an integer value'
                  },
                  :argline => 'char *string',
                  :sig => 'char *',
                  :description => 'Do something',
                  :lineto => 9,
                  :comments => "More explanation of what we do\n",
                  :decl => 'int some_function(char *string)',
                  :name => 'some_function'}]

    assert_equal expected, actual
  end

  def test_single_multiline_function
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

    raw_comments = <<EOF
Do something

More explanation of what we do

@param string a sequence of characters
@return an integer value
EOF

    actual = @parser.parse_text(name, contents)
    expected = [{:file => "function.h",
                  :line => 9,
                  :decl => "int some_function(\n    char *string,\n    size_t len)",
                  :body => "int some_function(\n    char *string,\n    size_t len);",
                  :rawComments => raw_comments.strip,
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
