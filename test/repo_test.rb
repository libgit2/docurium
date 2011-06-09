require File.expand_path "../test_helper", __FILE__
require 'base64'

context "Docurium Header Parsing" do
  setup do
    @path = File.dirname(__FILE__) + '/fixtures'
    @doc  = Docurium.new(@path)
    @doc.set_function_filter('git_')
    @doc.parse_headers
    @data = @doc.data
  end

  test "can parse header files" do
    assert_equal 14, @data[:groups].count
  end

  test "can group functions" do
    assert_equal 14, @data[:groups].size
    group, funcs = @data[:groups].first
    assert_equal 'blob', group
    assert_equal 6, funcs.size
    group, funcs = @data[:groups].last
    assert_equal 'misc', group
  end

end
