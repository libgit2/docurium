require 'json'
require 'tempfile'
require 'version_sorter'
require 'rocco'
require 'docurium/version'
require 'docurium/layout'
require 'libdetect'
require 'docurium/docparser'
require 'pp'
require 'rugged'
require 'redcarpet'
require 'redcarpet/compat'
require 'parallel'
require 'thread'

# Markdown expects the old redcarpet compat API, so let's tell it what
# to use
Rocco::Markdown = RedcarpetCompat

class Docurium
  attr_accessor :branch, :output_dir, :data, :head_data

  def initialize(config_file, repo = nil)
    raise "You need to specify a config file" if !config_file
    raise "You need to specify a valid config file" if !valid_config(config_file)
    @sigs = {}
    @head_data = nil
    @repo = repo || Rugged::Repository.discover(config_file)
  end

  def init_data(version = 'HEAD')
    data = {:files => [], :functions => {}, :callbacks => {}, :globals => {}, :types => {}, :prefix => ''}
    data[:prefix] = option_version(version, 'input', '')
    data
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

  def format_examples!(data, version)
    examples = []
    if ex = option_version(version, 'examples')
      if subtree = find_subtree(version, ex) # check that it exists
        index = Rugged::Index.new
        index.read_tree(subtree)

        files = []
        index.each do |entry|
          next unless entry[:path].match(/\.c$/)
          files << entry[:path]
        end

        files.each do |file|
          # highlight, roccoize and link
          rocco = Rocco.new(file, files, {:language => 'c'}) do
            ientry = index[file]
            blob = @repo.lookup(ientry[:oid])
            blob.content
          end

          extlen = -(File.extname(file).length + 1)
          rf_path = file[0..extlen] + '.html'
          rel_path = "ex/#{version}/#{rf_path}"

          rocco_layout = Rocco::Layout.new(rocco, @tf)
          # find out how deep our file is so we can use the right
          # number of ../ in the path
          depth = rel_path.count('/') - 1
          if depth == 0
            rocco_layout[:dirsup] = "./"
          else
            rocco_layout[:dirsup] = "../"*depth
          end

          rocco_layout.version = version
          rf = rocco_layout.render


          # look for function names in the examples and link
          id_num = 0
          data[:functions].each do |f, fdata|
            rf.gsub!(/#{f}([^\w])/) do |fmatch|
              extra = $1
              id_num += 1
              name = f + '-' + id_num.to_s
              # save data for cross-link
              data[:functions][f][:examples] ||= {}
              data[:functions][f][:examples][file] ||= []
              data[:functions][f][:examples][file] << rel_path + '#' + name
              "<a name=\"#{name}\" class=\"fnlink\" href=\"../../##{version}/group/#{fdata[:group]}/#{f}\">#{f}</a>#{extra}"
            end
          end

          # write example to the repo
          sha = @repo.write(rf, :blob)
          examples << [rel_path, sha]

          data[:examples] ||= []
          data[:examples] << [file, rel_path]
        end
      end
    end

    examples
  end

  def generate_doc_for(version)
    index = Rugged::Index.new
    read_subtree(index, version, option_version(version, 'input', ''))

    data = parse_headers(index, version, reference)
    examples = format_examples!(data, version)
    [data, examples]
  end

  def process_project(versions)
    nversions = versions.count
    Parallel.each_with_index(versions, finish: -> (version, index, result) do
      data, examples = result
      # There's still some work we need to do serially
      tally_sigs!(version, data)
      force_utf8(data)

      puts "Adding documentation for #{version} [#{index}/#{nversions}]"

      # Store it so we can show it at the end
      @head_data = data if version == 'HEAD'

      yield index, version, result if block_given?

    end) do |version, index|
      puts "Generating documentation for #{version} [#{index}/#{nversions}]"
      generate_doc_for(version)
    end
  end

  def generate_docs(options)
    output_index = Rugged::Index.new
    write_site(output_index)
    @tf = File.expand_path(File.join(File.dirname(__FILE__), 'docurium', 'layout.mustache'))
    versions = get_versions
    versions << 'HEAD'
    # If the user specified versions, validate them and overwrite
    if !(vers = options[:for]).empty?
      vers.each do |v|
        next if versions.include?(v)
        puts "Unknown version #{v}"
        exit(false)
      end
      versions = vers
    end

    process_project(versions) do |i, version, result|
      print "Writing documentation [#{i}/#{versions.count}]\r"
      data, examples = result

      sha = @repo.write(data.to_json, :blob)
      output_index.add(:path => "#{version}.json", :oid => sha, :mode => 0100644)
      examples.each do |path, id|
        output_index.add(:path => path, :oid => id, :mode => 0100644)
      end
    end

    if head_data
      puts ''
      show_warnings(head_data)
    end

    # We tally the signatures in the order they finished, which is
    # arbitrary due to the concurrency, so we need to sort them once
    # they've finished.
    sort_sigs!

    project = {
      :versions => versions.reverse,
      :github   => @options['github'],
      :name     => @options['name'],
      :signatures => @sigs,
    }
    sha = @repo.write(project.to_json, :blob)
    output_index.add(:path => "project.json", :oid => sha, :mode => 0100644)

    css = File.read(File.expand_path(File.join(File.dirname(__FILE__), 'docurium', 'css.css')))
    sha = @repo.write(css, :blob)
    output_index.add(:path => "ex/css.css", :oid => sha, :mode => 0100644)

    br = @options['branch']
    out "* writing to branch #{br}"
    refname = "refs/heads/#{br}"
    tsha = output_index.write_tree(@repo)
    puts "\twrote tree   #{tsha}"
    ref = @repo.references[refname]
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

  def force_utf8(data)
    # Walk the data to force strings encoding to UTF-8.
    if data.instance_of? Hash
      data.each do |key, value|
        if [:comment, :comments, :description].include?(key)
          data[key] = value.force_encoding('UTF-8') unless value.nil?
        else
          force_utf8(value)
        end
      end
    elsif data.respond_to?(:each)
      data.each { |x| force_utf8(x) }
    end
  end

  def show_warnings(data)
    out '* checking your api'

    # check for unmatched paramaters
    unmatched = []
    data[:functions].each do |f, fdata|
      unmatched << f if fdata[:comments] =~ /@param/
    end
    if unmatched.size > 0
      out '  - unmatched params in'
      unmatched.sort.each { |p| out ("\t" + p) }
    end

    # check for changed signatures
    sigchanges = []
    @sigs.each do |fun, sig_data|
      if sig_data[:changes]['HEAD']
        sigchanges << fun
      end
    end
    if sigchanges.size > 0
      out '  - signature changes in'
      sigchanges.sort.each { |p| out ("\t" + p) }
    end
  end

  def get_versions
    releases = @repo.tags
               .map { |tag| tag.name.gsub(%r(^refs/tags/), '') }
               .delete_if { |tagname| tagname.match(%r(-rc\d*$)) }
    VersionSorter.sort(releases)
  end

  def parse_headers(index, version)
    headers = index.map { |e| e[:path] }.grep(/\.h$/)

    files = headers.map do |file|
      [file, @repo.lookup(index[file][:oid]).content]
    end

    data = init_data(version)
    parser = DocParser.new
    headers.each do |header|
      records = parser.parse_file(header, files)
      update_globals!(data, records)
    end

    data[:groups] = group_functions!(data)
    data[:types] = data[:types].sort # make it an assoc array
    find_type_usage!(data)

    data
  end

  private

  def tally_sigs!(version, data)
    @lastsigs ||= {}
    data[:functions].each do |fun_name, fun_data|
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

  def sort_sigs!
    @sigs.keys.each do |fn|
      VersionSorter.sort!(@sigs[fn][:exists])
      # Put HEAD at the back
      @sigs[fn][:exists] << @sigs[fn][:exists].shift
    end
  end

  def find_subtree(version, path)
    tree = nil
    if version == 'HEAD'
      tree = @repo.head.target.tree
    else
      trg = @repo.references["refs/tags/#{version}"].target
      if(trg.kind_of? Rugged::Tag::Annotation)
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

  def group_functions!(data)
    func = {}
    data[:functions].each_pair do |key, value|
      if @options['prefix']
        k = key.gsub(@options['prefix'], '')
      else
        k = key
      end
      group, rest = k.split('_', 2)
      if group.empty?
        puts "empty group for function #{key}"
        next
      end
      data[:functions][key][:group] = group
      func[group] ||= []
      func[group] << key
      func[group].sort!
    end
    func.to_a.sort
  end

  def find_type_usage!(data)
    # go through all the functions and callbacks and see where other types are used and returned
    # store them in the types data
    h = {}
    h.merge!(data[:functions])
    h.merge!(data[:callbacks])
    h.each do |func, fdata|
      data[:types].each_with_index do |tdata, i|
        type = tdata[0]
        data[:types][i][1][:used] ||= {:returns => [], :needs => []}
        if fdata[:return][:type].index(/#{type}[ ;\)\*]?/)
          data[:types][i][1][:used][:returns] << func
          data[:types][i][1][:used][:returns].sort!
        end
        if fdata[:argline].index(/#{type}[ ;\)\*]?/)
          data[:types][i][1][:used][:needs] << func
          data[:types][i][1][:used][:needs].sort!
        end
      end
    end
  end

  def update_globals!(data, recs)
    return if recs.empty?

    wanted = {
      :functions => %W/type value file line lineto args argline sig return group description comments/.map(&:to_sym),
      :types => %W/decl type value file line lineto block tdef description comments fields/.map(&:to_sym),
      :globals => %W/value file line comments/.map(&:to_sym),
      :meta => %W/brief defgroup ingroup comments/.map(&:to_sym),
    }

    file_map = {}

    md = Redcarpet::Markdown.new(Redcarpet::Render::HTML.new({}), :no_intra_emphasis => true)
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
      when :function, :callback
        t = r[:type] == :function ? :functions : :callbacks
        data[t][r[:name]] ||= {}
        wanted[:functions].each do |k|
          next unless r.has_key? k
          if k == :description || k == :comments
            contents = md.render r[k]
          else
            contents = r[k]
          end
          data[t][r[:name]][k] = contents
        end
        file_map[r[:file]][:functions] << r[:name]

      when :define, :macro
        data[:globals][r[:decl]] ||= {}
        wanted[:globals].each do |k|
          next unless r.has_key? k
          if k == :description || k == :comments
            data[:globals][r[:decl]][k] = md.render r[k]
          else
            data[:globals][r[:decl]][k] = r[k]
          end
        end

      when :file
        wanted[:meta].each do |k|
          file_map[r[:file]][:meta][k] = r[k] if r.has_key?(k)
        end

      when :enum
        if !r[:name]
          # Explode unnamed enum into multiple global defines
          r[:decl].each do |n|
            data[:globals][n] ||= {
              :file => r[:file], :line => r[:line],
              :value => "", :comments => md.render(r[:comments]),
            }
            m = /#{Regexp.quote(n)}/.match(r[:body])
            if m
              data[:globals][n][:line] += m.pre_match.scan("\n").length
              if m.post_match =~ /\s*=\s*([^,\}]+)/
                data[:globals][n][:value] = $1
              end
            end
          end
        else # enum has name
          data[:types][r[:name]] ||= {}
          wanted[:types].each do |k|
            next unless r.has_key? k
            contents = r[k]
            if k == :comments
              contents = md.render r[k]
            elsif k == :block
              old_block = data[:types][r[:name]][k]
              contents = old_block ? [old_block, r[k]].join("\n") : r[k]
            elsif k == :fields
              type = data[:types][r[:name]]
              type[:fields] = []
              r[:fields].each do |f|
                f[:comments] = md.render(f[:comments])
              end
            end
            data[:types][r[:name]][k] = contents
          end
        end

      when :struct, :fnptr
        data[:types][r[:name]] ||= {}
        known = data[:types][r[:name]]
        r[:value] ||= r[:name]
        # we don't want to override "opaque" structs with typedefs or
        # "public" documentation
        unless r[:tdef].nil? and known[:fields] and known[:comments] and known[:description]
          wanted[:types].each do |k|
            next unless r.has_key? k
            if k == :comments
              data[:types][r[:name]][k] = md.render r[k]
            else
              data[:types][r[:name]][k] = r[k]
            end
          end
        else
          # We're about to skip that type. Just make sure we preserve the
          # :fields comment
          if r[:fields] and known[:fields].empty?
            data[:types][r[:name]][:fields] = r[:fields]
          end
        end
        if r[:type] == :fnptr
          data[:types][r[:name]][:type] = "function pointer"
        end

      else
        # Anything else we want to record?
      end

    end

    data[:files] << file_map.values[0]
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
