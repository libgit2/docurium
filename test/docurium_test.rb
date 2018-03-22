require 'minitest/autorun'
require 'docurium'
require 'rugged'

class DocuriumTest < Minitest::Test

  def setup
    @dir = Dir.mktmpdir()

    @repo = Rugged::Repository.init_at(@dir, :bare)

    # Create an index as we would have read from the user's repository
    index = Rugged::Index.new
    headers = File.dirname(__FILE__) + '/fixtures/git2/'
    Dir.entries(headers).each do |rel_path|
      path = File.join(headers, rel_path)
      next if File.directory? path
      id = @repo.write(File.read(path), :blob)
      index.add(:path => rel_path, :oid => id, :mode => 0100644)
    end

    @path = File.dirname(__FILE__) + '/fixtures/git2/api.docurium'
    @doc = Docurium.new(@path, {}, @repo)
    @data = @doc.parse_headers(index, 'HEAD')
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_can_parse
    refute_nil @data
    assert_equal [:files, :functions, :callbacks, :globals, :types, :prefix, :groups], @data.keys
    files = %w(blob.h callback.h cherrypick.h commit.h common.h errors.h index.h object.h odb.h odb_backend.h oid.h refs.h repository.h revwalk.h signature.h tag.h tree.h types.h)
    assert_equal files, @data[:files].map {|d| d[:file] }
  end

  def test_can_parse_headers
    keys = @data.keys.map { |k| k.to_s }.sort
    assert_equal ['callbacks', 'files', 'functions', 'globals', 'groups', 'prefix', 'types'], keys
    assert_equal 155, @data[:functions].size
  end

  def test_can_extract_enum_from_define
    skip("this isn't something we do")
    assert_equal 41, @data[:globals].size
    idxentry = @data[:types].find { |a| a[0] == 'GIT_IDXENTRY' }
    assert idxentry
    assert_equal 75, idxentry[1][:lineto]
    # this one is on the last doc block
    assert idxentry[1][:block].include? 'GIT_IDXENTRY_EXTENDED2'
    # from an earlier block, should not get overwritten
    assert idxentry[1][:block].include? 'GIT_IDXENTRY_UPDATE'
  end

  def test_can_extract_structs_and_enums
    skip("we don't auto-create enums, so the number is wrong")
    assert_equal 25, @data[:types].size
  end

  def test_can_find_type_usage
    oid = @data[:types].assoc('git_oid')
    oid_returns = [
      "git_commit_id",
      "git_commit_parent_oid",
      "git_commit_tree_oid",
      "git_object_id",
      "git_odb_object_id",
      "git_oid_shorten_new",
      "git_reference_oid",
      "git_tag_id",
      "git_tag_target_oid",
      "git_tree_entry_id",
      "git_tree_id"
    ]
    assert_equal oid_returns, oid[1][:used][:returns]
    oid_needs = [
      "git_blob_create_frombuffer",
      "git_blob_create_fromfile",
      "git_blob_lookup",
      "git_commit_create",
      "git_commit_create_o",
      "git_commit_create_ov",
      "git_commit_create_v",
      "git_commit_lookup",
      "git_object_lookup",
      "git_odb_exists",
      "git_odb_hash",
      "git_odb_open_rstream",
      "git_odb_read",
      "git_odb_read_header",
      "git_odb_write",
      "git_oid_allocfmt",
      "git_oid_cmp",
      "git_oid_cpy",
      "git_oid_fmt",
      "git_oid_mkraw",
      "git_oid_mkstr",
      "git_oid_pathfmt",
      "git_oid_shorten_add",
      "git_oid_shorten_free",
      "git_oid_to_string",
      "git_reference_create_oid",
      "git_reference_create_oid_f",
      "git_reference_set_oid",
      "git_revwalk_hide",
      "git_revwalk_next",
      "git_revwalk_push",
      "git_tag_create",
      "git_tag_create_f",
      "git_tag_create_fo",
      "git_tag_create_frombuffer",
      "git_tag_create_o",
      "git_tag_lookup",
      "git_tree_create_fromindex",
      "git_tree_lookup",
      "git_treebuilder_insert",
      "git_treebuilder_write"
    ]
    assert_equal oid_needs, oid[1][:used][:needs].sort
  end

  def test_can_parse_normal_functions
    func = @data[:functions]['git_blob_rawcontent']
    assert_equal "<p>Get a read-only buffer with the raw content of a blob.</p>\n",  func[:description]
    assert_equal 'const void *',  func[:return][:type]
    assert_equal ' the pointer; NULL if the blob has no contents',  func[:return][:comment]
    assert_equal 84,              func[:line]
    assert_equal 84,              func[:lineto]
    assert_equal 'blob.h',        func[:file]
    assert_equal 'git_blob *blob',func[:argline]
    assert_equal 'blob',          func[:args][0][:name]
    assert_equal 'git_blob *',    func[:args][0][:type]
    assert_equal 'pointer to the blob',  func[:args][0][:comment]
  end

  def test_can_parse_defined_functions
    func = @data[:functions]['git_tree_lookup']
    assert_equal 'int',     func[:return][:type]
    assert_equal ' 0 on success; error code otherwise',     func[:return][:comment]
    assert_equal 50,        func[:line]
    assert_equal 'tree.h',  func[:file]
    assert_equal 'id',               func[:args][2][:name]
    assert_equal 'const git_oid *',  func[:args][2][:type]
    assert_equal 'identity of the tree to locate.',  func[:args][2][:comment]
  end

  def test_can_parse_function_cast_args
    func = @data[:functions]['git_reference_listcb']
    assert_equal 'int',             func[:return][:type]
    assert_equal ' 0 on success; error code otherwise',  func[:return][:comment]
    assert_equal 321,               func[:line]
    assert_equal 'refs.h',          func[:file]
    assert_equal 'repo',              func[:args][0][:name]
    assert_equal 'git_repository *',  func[:args][0][:type]
    assert_equal 'list_flags',      func[:args][1][:name]
    assert_equal 'unsigned int',    func[:args][1][:type]
    assert_equal 'callback',        func[:args][2][:name]
    assert_equal 'int (*)(const char *, void *)', func[:args][2][:type]
    assert_equal 'Function which will be called for every listed ref', func[:args][2][:comment]
    expect_comment =<<-EOF
<p>The listed references may be filtered by type, or using
 a bitwise OR of several types. Use the magic value
 <code>GIT_REF_LISTALL</code> to obtain all references, including
 packed ones.</p>

<p>The <code>callback</code> function will be called for each of the references
 in the repository, and will receive the name of the reference and
 the <code>payload</code> value passed to this method.</p>
    EOF
    assert_equal expect_comment.split("\n"), func[:comments].split("\n")
  end

  def test_can_get_the_full_description_from_multi_liners
    func = @data[:functions]['git_commit_create_o']
    desc = "<p>Create a new commit in the repository using <code>git_object</code>\n instances as parameters.</p>\n"
    assert_equal desc, func[:description]
  end

  def test_can_group_functions
    groups = %w(blob cherrypick commit index lasterror object odb oid reference repository revwalk signature strerror tag tree treebuilder work)
    assert_equal groups, @data[:groups].map {|g| g[0]}.sort
    group, funcs = @data[:groups].first
    assert_equal 'blob', group
    assert_equal 6, funcs.size
  end

  def test_can_store_mutliple_enum_doc_sections
    skip("this isn't something we do")
    idxentry = @data[:types].find { |a| a[0] == 'GIT_IDXENTRY' }
    assert idxentry, "GIT_IDXENTRY did not get automatically created"
    assert_equal 2, idxentry[1][:sections].size
  end

  def test_can_parse_callback
    cb = @data[:callbacks]['git_callback_do_work']
    # we can mostly assume that the rest works as it's the same as for the functions
    assert_equal 'int', cb[:return][:type]
  end

end
