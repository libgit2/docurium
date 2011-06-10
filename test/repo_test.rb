require File.expand_path "../test_helper", __FILE__
require 'base64'

context "Docurium Header Parsing" do
  setup do
    @path = File.dirname(__FILE__) + '/fixtures/git2'
    @doc  = Docurium.new(@path)
    @doc.set_function_filter('git_')
    @doc.parse_headers
    @data = @doc.data
  end

  test "can parse header files" do
    keys = @data.keys.map { |k| k.to_s }.sort
    assert_equal ['files', 'functions', 'globals', 'groups', 'prefix', 'types'], keys
    assert_equal 150, @data[:functions].size
  end

  test "can extract globals" do
    assert_equal 55, @data[:globals].size
    entry = @data[:globals]['GIT_IDXENTRY_EXTENDED2']
    assert_equal "index.h", entry[:file]
    assert_equal 73, entry[:line]
  end

  test "can extract structs and enums" do
    assert_equal 25, @data[:types].size
  end

  test "can parse sequential sigs" do
    func = @data[:functions]['git_odb_backend_pack']
    assert_equal 'const char *', func[:args][1][:type]
    func = @data[:functions]['git_odb_backend_loose']
    assert_equal 'const char *', func[:args][1][:type]
  end

  test "can parse normal functions" do
    func = @data[:functions]['git_blob_rawcontent']
    assert_equal 'Get a read-only buffer with the raw content of a blob.',  func[:description]
    assert_equal 'const void *',  func[:return][:type]
    assert_equal 'the pointer; NULL if the blob has no contents',  func[:return][:comment]
    assert_equal 73,              func[:line]
    assert_equal 84,              func[:lineto]
    assert_equal 'blob.h',        func[:file]
    assert_equal 'git_blob *blob',func[:argline]
    assert_equal 'blob',          func[:args][0][:name]
    assert_equal 'git_blob *',    func[:args][0][:type]
    assert_equal 'pointer to the blob',  func[:args][0][:comment]
  end

  test "can parse defined functions" do
    func = @data[:functions]['git_tree_lookup']
    assert_equal 'int',     func[:return][:type]
    assert_equal '0 on success; error code otherwise',     func[:return][:comment]
    assert_equal 42,        func[:line]
    assert_equal 'tree.h',  func[:file]
    assert_equal 'id',               func[:args][2][:name]
    assert_equal 'const git_oid *',  func[:args][2][:type]
    assert_equal 'identity of the tree to locate.',  func[:args][2][:comment]
  end

  test "can parse function cast args" do
    func = @data[:functions]['git_reference_listcb']
    assert_equal 'int',             func[:return][:type]
    assert_equal '0 on success; error code otherwise',  func[:return][:comment]
    assert_equal 301,               func[:line]
    assert_equal 'refs.h',          func[:file]
    assert_equal 'repo',              func[:args][0][:name]
    assert_equal 'git_repository *',  func[:args][0][:type]
    assert_equal 'list_flags',      func[:args][1][:name]
    assert_equal 'unsigned int',    func[:args][1][:type]
    assert_equal 'callback',        func[:args][2][:name]
    assert_equal 'int(*)(const char *, void *)', func[:args][2][:type]
    assert_equal 'Function which will be called for every listed ref', func[:args][2][:comment]
    assert_equal 8, func[:comments].split("\n").size
  end

  test "can get the full description from multi liners" do
    func = @data[:functions]['git_commit_create_o']
    desc = "Create a new commit in the repository using `git_object` instances as parameters."
    assert_equal desc, func[:description]
  end

  test "can group functions" do
    assert_equal 15, @data[:groups].size
    group, funcs = @data[:groups].first
    assert_equal 'blob', group
    assert_equal 6, funcs.size
  end

  test "can parse data structures" do
  end

end
