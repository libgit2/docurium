require 'json'
require 'tempfile'
require 'version_sorter'
require 'rocco'
require 'docurium/version'
require 'docurium/layout'
require 'docurium/cparser'
require 'pp'
require 'rugged'
require 'redcarpet'

class Docurium
  attr_accessor :branch, :output_dir, :data

  def initialize(config_file)
    raise "You need to specify a config file" if !config_file
    raise "You need to specify a valid config file" if !valid_config(config_file)
    @sigs = {}
    @groups = {}
    repo_path = Rugged::Repository.discover('.')
    @repo = Rugged::Repository.new(repo_path)
    clear_data
  end

  def clear_data(version = 'HEAD')
    @data = {:files => [], :functions => {}, :globals => {}, :types => {}, :prefix => ''}
    @data[:prefix] = option_version(version, 'input', '')
  end

  def option_version(version, option, default = nil)
    if @options['legacy']
      if valhash = @options['legacy'][option]
        valhash.each do |value, versions|
          return value if versions.include?(version)
        end
      end
    end
    opt = @options[option]
    opt = default if !opt
    opt
  end

  def generate_docs
    out "* generating docs"
    output_index = Rugged::Index.new
    write_site(output_index)
    versions = get_versions
    versions << 'HEAD'
    versions.each do |version|
      out "  - processing version #{version}"
      index = @repo.index
      index.clear
      clear_data(version)
      read_subtree(index, version, @data[:prefix])
      parse_headers(index)
      tally_sigs(version)

      tf = File.expand_path(File.join(File.dirname(__FILE__), 'docurium', 'layout.mustache'))
      if ex = option_version(version, 'examples')
        if subtree = find_subtree(version, ex) # check that it exists
          index.read_tree(subtree)
          out "  - processing examples for #{version}"

          files = []
          index.each do |entry|
            next unless entry[:path].match(/\.c$/)
            files << entry[:path]
          end

          files.each do |file|
            out "    # #{file}"

            # highlight, roccoize and link
            rocco = Rocco.new(file, files, {:language => 'c'}) do
              ientry = index[file]
              blob = @repo.lookup(ientry[:oid])
              blob.content
            end
            rocco_layout = Rocco::Layout.new(rocco, tf)
            rocco_layout.version = version
            rf = rocco_layout.render

            extlen = -(File.extname(file).length + 1)
            rf_path = file[0..extlen] + '.html'
            rel_path = "ex/#{version}/#{rf_path}"

            # look for function names in the examples and link
            id_num = 0
            @data[:functions].each do |f, fdata|
              rf.gsub!(/#{f}([^\w])/) do |fmatch|
                extra = $1
                id_num += 1
                name = f + '-' + id_num.to_s
                # save data for cross-link
                @data[:functions][f][:examples] ||= {}
                @data[:functions][f][:examples][file] ||= []
                @data[:functions][f][:examples][file] << rel_path + '#' + name
                "<a name=\"#{name}\" class=\"fnlink\" href=\"../../##{version}/group/#{fdata[:group]}/#{f}\">#{f}</a>#{extra}"
              end
            end

            # write example to the repo
            sha = @repo.write(rf, :blob)
            output_index.add(:path => rel_path, :oid => sha, :mode => 0100644)

            @data[:examples] ||= []
            @data[:examples] << [file, rel_path]
          end
        end

        if version == 'HEAD'
          show_warnings
        end
      end

      sha = @repo.write(@data.to_json, :blob)
      output_index.add(:path => "#{version}.json", :oid => sha, :mode => 0100644)
    end

    project = {
      :versions => versions.reverse,
      :github   => @options['github'],
      :name     => @options['name'],
      :signatures => @sigs,
      :groups   => @groups
    }
    sha = @repo.write(project.to_json, :blob)
    output_index.add(:path => "project.json", :oid => sha, :mode => 0100644)

    br = @options['branch']
    out "* writing to branch #{br}"
    refname = "refs/heads/#{br}"
    tsha = output_index.write_tree(@repo)
    puts "\twrote tree   #{tsha}"
    ref = Rugged::Reference.lookup(@repo, refname)
    user = { :name => @repo.config['user.name'], :email => @repo.config['user.email'], :time => Time.now }
    options = {}
    options[:tree] = tsha
    options[:author] = user
    options[:committer] = user
    options[:message] = 'generated docs'
    options[:parents] = ref ? [ref.target] : []
    options[:update_ref] = refname
    csha = Rugged::Commit.create(@repo, options)
    puts "\twrote commit #{csha}"
    puts "\tupdated #{br}"
  end

  def show_warnings
    out '* checking your api'

    # check for unmatched paramaters
    unmatched = []
    @data[:functions].each do |f, fdata|
      unmatched << f if fdata[:comments] =~ /@param/
    end
    if unmatched.size > 0
      out '  - unmatched params in'
      unmatched.sort.each { |p| out ("\t" + p) }
    end

    # check for changed signatures
    sigchanges = []
    @sigs.each do |fun, data|
      if data[:changes]['HEAD']
        sigchanges << fun
      end
    end
    if sigchanges.size > 0
      out '  - signature changes in'
      sigchanges.sort.each { |p| out ("\t" + p) }
    end
  end

  def get_versions
    tags = []
    @repo.tags.each { |tag| tags << tag.gsub(%r(^refs/tags/), '') }
    VersionSorter.sort(tags)
  end

  def parse_headers(index)
    headers(index).each do |header|
      records = parse_header(index, header)
      update_globals(records)
    end

    @data[:groups] = group_functions
    @data[:types] = @data[:types].sort # make it an assoc array
    find_type_usage
  end

  private

  def tally_sigs(version)
    @lastsigs ||= {}
    @data[:functions].each do |fun_name, fun_data|
      if !@sigs[fun_name]
        @sigs[fun_name] ||= {:exists => [], :changes => {}}
      else
        if @lastsigs[fun_name] != fun_data[:sig]
          @sigs[fun_name][:changes][version] = true
        end
      end
      @sigs[fun_name][:exists] << version
      @lastsigs[fun_name] = fun_data[:sig]
    end
  end

  def find_subtree(version, path)
    tree = nil
    if version == 'HEAD'
      tree = @repo.lookup(@repo.head.target).tree
    else
      trg = @repo.lookup(Rugged::Reference.lookup(@repo, "refs/tags/#{version}").target)
      if(trg.class == Rugged::Tag)
        trg = trg.target
      end

      tree = trg.tree
    end

    begin
      tree_entry = tree.path(path)
      @repo.lookup(tree_entry[:oid])
    rescue Rugged::TreeError
      nil
    end
  end

  def read_subtree(index, version, path)
    tree = find_subtree(version, path)
    index.read_tree(tree)
  end

  def valid_config(file)
    return false if !File.file?(file)
    fpath = File.expand_path(file)
    @project_dir = File.dirname(fpath)
    @config_file = File.basename(fpath)
    @options = JSON.parse(File.read(fpath))
    !!@options['branch']
  end

  def group_functions
    func = {}
    @data[:functions].each_pair do |key, value|
      if @options['prefix']
        k = key.gsub(@options['prefix'], '')
      else
        k = key
      end
      group, rest = k.split('_', 2)
      next if group.empty?
      if !rest
        group = value[:file].gsub('.h', '').gsub('/', '_')
      end
      @data[:functions][key][:group] = group
      @groups[key] = group
      func[group] ||= []
      func[group] << key
      func[group].sort!
    end
    misc = []
    func.to_a.sort
  end

  def headers(index = nil)
    h = []
    index.each do |entry|
      next unless entry[:path].match(/\.h$/)
      h << entry[:path]
    end
    h
  end

  def find_type_usage
    # go through all the functions and see where types are used and returned
    # store them in the types data
    @data[:functions].each do |func, fdata|
      @data[:types].each_with_index do |tdata, i|
        type, typeData = tdata
        @data[:types][i][1][:used] ||= {:returns => [], :needs => []}
        if fdata[:return][:type].index(/#{type}[ ;\)\*]/)
          @data[:types][i][1][:used][:returns] << func
          @data[:types][i][1][:used][:returns].sort!
        end
        if fdata[:argline].index(/#{type}[ ;\)\*]/)
          @data[:types][i][1][:used][:needs] << func
          @data[:types][i][1][:used][:needs].sort!
        end
      end
    end
  end

  def parse_header(index, path)
    id = index[path][:oid]
    blob = @repo.lookup(id)
    parser = Docurium::CParser.new
    parser.parse_text(path, blob.content)
  end

  def update_globals(recs)
    wanted = {
      :functions => %W/type value file line lineto args argline sig return group description comments/.map(&:to_sym),
      :types => %W/type value file line lineto block tdef comments/.map(&:to_sym),
      :globals => %W/value file line comments/.map(&:to_sym),
      :meta => %W/brief defgroup ingroup comments/.map(&:to_sym),
    }

    file_map = {}

    md = Redcarpet::Markdown.new Redcarpet::Render::HTML, :no_intra_emphasis => true
    recs.each do |r|

      # initialize filemap for this file
      file_map[r[:file]] ||= {
        :file => r[:file], :functions => [], :meta => {}, :lines => 0
      }
      if file_map[r[:file]][:lines] < r[:lineto]
        file_map[r[:file]][:lines] = r[:lineto]
      end

      # process this type of record
      case r[:type]
      when :function
        @data[:functions][r[:name]] ||= {}
        wanted[:functions].each do |k|
          next unless r.has_key? k
          conents = nil
          if k == :description || k == :comments
            contents = md.render r[k]
          else
            contents = r[k]
          end
          @data[:functions][r[:name]][k] = contents
        end
        file_map[r[:file]][:functions] << r[:name]

      when :define, :macro
        @data[:globals][r[:decl]] ||= {}
        wanted[:globals].each do |k|
          @data[:globals][r[:decl]][k] = r[k] if r.has_key?(k)
        end

      when :file
        wanted[:meta].each do |k|
          file_map[r[:file]][:meta][k] = r[k] if r.has_key?(k)
        end

      when :enum
        if !r[:name]
          # Explode unnamed enum into multiple global defines
          r[:decl].each do |n|
            @data[:globals][n] ||= {
              :file => r[:file], :line => r[:line],
              :value => "", :comments => r[:comments],
            }
            m = /#{Regexp.quote(n)}/.match(r[:body])
            if m
              @data[:globals][n][:line] += m.pre_match.scan("\n").length
              if m.post_match =~ /\s*=\s*([^,\}]+)/
                @data[:globals][n][:value] = $1
              end
            end
          end
        else
          @data[:types][r[:name]] ||= {}
          wanted[:types].each do |k|
            @data[:types][r[:name]][k] = r[k] if r.has_key?(k)
          end
        end

      when :struct, :fnptr
        @data[:types][r[:name]] ||= {}
        r[:value] ||= r[:name]
        wanted[:types].each do |k|
          @data[:types][r[:name]][k] = r[k] if r.has_key?(k)
        end
        if r[:type] == :fnptr
          @data[:types][r[:name]][:type] = "function pointer"
        end

      else
        # Anything else we want to record?
      end

    end

    @data[:files] << file_map.values[0]
  end

  def add_dir_to_index(index, prefix, dir)
    Dir.new(dir).each do |filename|
      next if [".", ".."].include? filename
      name = File.join(dir, filename)
      if File.directory? name
        add_dir_to_index(index, prefix, name)
      else
        rel_path = name.gsub(prefix, '')
        content = File.read(name)
        sha = @repo.write(content, :blob)
        index.add(:path => rel_path, :oid => sha, :mode => 0100644)
      end
    end
  end

  def write_site(index)
    here = File.expand_path(File.dirname(__FILE__))
    dirname = File.join(here, '..', 'site')
    dirname = File.realpath(dirname)
    add_dir_to_index(index, dirname + '/', dirname)
  end

  def out(text)
    puts text
  end
end
