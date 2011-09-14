require 'json'
require 'tempfile'
require 'version_sorter'
require 'rocco'
require 'docurium/layout'
require 'pp'

class Docurium
  Version = VERSION = '0.0.5'

  attr_accessor :branch, :output_dir, :data

  def initialize(config_file)
    raise "You need to specify a config file" if !config_file
    raise "You need to specify a valid config file" if !valid_config(config_file)
    @sigs = {}
    @groups = {}
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
    outdir = mkdir_temp
    copy_site(outdir)
    versions = get_versions
    versions << 'HEAD'
    versions.each do |version|
      out "  - processing version #{version}"
      workdir = mkdir_temp
      Dir.chdir(workdir) do
        clear_data(version)
        checkout(version, workdir)
        parse_headers
        tally_sigs(version)
      end

      tf = File.expand_path(File.join(File.dirname(__FILE__), 'docurium', 'layout.mustache'))
      if ex = option_version(version, 'examples')
        workdir = mkdir_temp
        Dir.chdir(workdir) do
          with_git_env(workdir) do
            `git rev-parse #{version}:#{ex} 2>&1` # check that it exists
            if $?.exitstatus == 0
              out "  - processing examples for #{version}"
              `git read-tree #{version}:#{ex}`
              `git checkout-index -a`

              files = []
              Dir.glob("**/*.c") do |file|
                next if !File.file?(file)
                files << file
              end
              files.each do |file|
                out "    # #{file}"

                # highlight, roccoize and link
                rocco = Rocco.new(file, files, {:language => 'c'})
                rocco_layout = Rocco::Layout.new(rocco, tf)
                rocco_layout.version = version
                rf = rocco_layout.render

                rf_path = File.basename(file).split('.')[0..-2].join('.') + '.html'
                rel_path = "ex/#{version}/#{rf_path}"
                rf_path = File.join(outdir, rel_path)

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

                # write example to docs directory
                FileUtils.mkdir_p(File.dirname(rf_path))
                File.open(rf_path, 'w+') do |f|
                  @data[:examples] ||= []
                  @data[:examples] << [file, rel_path]
                  f.write(rf)
                end
              end
            end
          end
        end

        if version == 'HEAD'
          show_warnings
        end
      end

      File.open(File.join(outdir, "#{version}.json"), 'w+') do |f|
        f.write(@data.to_json)
      end
    end

    Dir.chdir(outdir) do
      project = {
        :versions => versions.reverse,
        :github   => @options['github'],
        :name     => @options['name'],
        :signatures => @sigs,
        :groups   => @groups
      }
      File.open("project.json", 'w+') do |f|
        f.write(project.to_json)
      end
    end

    if br = @options['branch']
      out "* writing to branch #{br}"
      ref = "refs/heads/#{br}"
      with_git_env(outdir) do
        psha = `git rev-parse #{ref}`.chomp
        `git add -A`
        tsha = `git write-tree`.chomp
        puts "\twrote tree   #{tsha}"
        if(psha == ref)
          csha = `echo 'generated docs' | git commit-tree #{tsha}`.chomp
        else
          csha = `echo 'generated docs' | git commit-tree #{tsha} -p #{psha}`.chomp
        end
        puts "\twrote commit #{csha}"
        `git update-ref -m 'generated docs' #{ref} #{csha}`
        puts "\tupdated #{br}"
      end
    else
      final_dir = File.join(@project_dir, @options['output'] || 'docs')
      out "* output html in #{final_dir}"
      FileUtils.mkdir_p(final_dir)
      Dir.chdir(final_dir) do
        FileUtils.cp_r(File.join(outdir, '.'), '.') 
      end
    end
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
    VersionSorter.sort(git('tag').split("\n"))
  end

  def parse_headers
    headers.each do |header|
      parse_header(header)
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

  def git(command)
    out = ''
    Dir.chdir(@project_dir) do
      out = `git #{command}`
    end
    out.strip
  end

  def checkout(version, workdir)
    with_git_env(workdir) do
      `git read-tree #{version}:#{@data[:prefix]}`
      `git checkout-index -a`
    end
  end

  def with_git_env(workdir)
    ENV['GIT_INDEX_FILE'] = mkfile_temp
    ENV['GIT_WORK_TREE'] = workdir
    ENV['GIT_DIR'] = File.join(@project_dir, '.git')
    yield
    ENV.delete('GIT_INDEX_FILE')
    ENV.delete('GIT_WORK_TREE')
    ENV.delete('GIT_DIR')
  end

  def valid_config(file)
    return false if !File.file?(file)
    fpath = File.expand_path(file)
    @project_dir = File.dirname(fpath)
    @config_file = File.basename(fpath)
    @options = JSON.parse(File.read(fpath))
    true
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

  def headers
    h = []
    Dir.glob(File.join('**/*.h')).each do |header|
      next if !File.file?(header)
      h << header
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

  def header_content(header_path)
    File.readlines(header_path)
  end

  def parse_header(filepath)
    lineno = 0
    content = header_content(filepath)

    # look for structs and enums
    in_block = false
    block = ''
    linestart = 0
    tdef, type, name = nil
    content.each do |line|
      lineno += 1
      line = line.strip

      if line[0, 1] == '#' #preprocessor
        if m = /\#define (.*?) (.*)/.match(line)
          @data[:globals][m[1]] = {:value => m[2].strip, :file => filepath, :line => lineno}
        else
          next
        end
      end

      if m = /^(typedef )*(struct|enum) (.*?)(\{|(\w*?);)/.match(line)
        tdef = m[1] # typdef or nil
        type = m[2] # struct or enum
        name = m[3] # name or nil
        linestart = lineno
        name.strip! if name
        tdef.strip! if tdef
        if m[4] == '{'
          # struct or enum
          in_block = true
        else
          # single line, probably typedef
          val = m[4].gsub(';', '').strip
          if !name.empty?
            name = name.gsub('*', '').strip
            @data[:types][name] = {:tdef => tdef, :type => type, :value => val, :file => filepath, :line => lineno}
          end
        end
      elsif m = /\}(.*?);/.match(line)
        if !m[1].strip.empty?
          name = m[1].strip
        end
        name = name.gsub('*', '').strip
        @data[:types][name] = {:block => block, :tdef => tdef, :type => type, :value => val, :file => filepath, :line => linestart, :lineto => lineno}
        in_block = false
        block = ''
      elsif in_block
        block += line + "\n"
      end
    end
    
    in_comment = false
    in_block = false
    current = -1
    data = []
    lineno = 0
    # look for functions
    content.each do |line|
      lineno += 1
      line = line.strip
      next if line.size == 0
      next if line[0, 1] == '#'
      in_block = true if line =~ /\{/
      if m = /(.*?)\/\*(.*?)\*\//.match(line)
        code = m[1]
        comment = m[2]
        current += 1
        data[current] ||= {:comments => clean_comment(comment), :code => [code], :line => lineno}
      elsif m = /(.*?)\/\/(.*?)/.match(line)
        code = m[1]
        comment = m[2]
        current += 1
        data[current] ||= {:comments => clean_comment(comment), :code => [code], :line => lineno}
      else
        if line =~ /\/\*/
          in_comment = true  
          current += 1
        elsif current == -1
          current += 1
        end
        data[current] ||= {:comments => '', :code => [], :line => lineno}
        data[current][:lineto] = lineno
        if in_comment
          data[current][:comments] += clean_comment(line) + "\n"
        else
          data[current][:code] << line
        end
        if (m = /(.*?);$/.match(line)) && (data[current][:code].size > 0) && !in_block
          current += 1
        end
        in_comment = false if line =~ /\*\//
        in_block = false if line =~ /\}/
      end
    end
    data.compact!
    meta  = extract_meta(data)
    funcs = extract_functions(filepath, data)
    @data[:files] << {:file => filepath, :meta => meta, :functions => funcs, :lines => lineno}
  end

  def clean_comment(comment)
    comment = comment.gsub(/^\/\//, '')
    comment = comment.gsub(/^\/\**/, '')
    comment = comment.gsub(/^\**/, '')
    comment = comment.gsub(/^[\w\*]*\//, '')
    comment
  end

  # go through all the comment blocks and extract:
  #  @file, @brief, @defgroup and @ingroup
  def extract_meta(data)
    file, brief, defgroup, ingroup = nil
    data.each do |block|
      block[:comments].each do |comment|
        m = []
        file  = m[1] if m = /@file (.*?)$/.match(comment)
        brief = m[1] if m = /@brief (.*?)$/.match(comment)
        defgroup = m[1] if m = /@defgroup (.*?)$/.match(comment)
        ingroup  = m[1] if m = /@ingroup (.*?)$/.match(comment)
      end
    end
    {:file => file, :brief => brief, :defgroup => defgroup, :ingroup => ingroup}
  end

  def extract_functions(file, data)
    @data[:functions]
    funcs = []
    data.each do |block|
      ignore = false
      code = block[:code].join(" ")
      code = code.gsub(/\{(.*)\}/, '') # strip inline code
      rawComments = block[:comments]
      comments = block[:comments]

      if m = /^(.*?) ([a-zA-Z_]+)\((.*)\)/.match(code)
        ret  = m[1].strip
        if r = /\((.*)\)/.match(ret) # strip macro
          ret = r[1]
        end
        fun  = m[2].strip
        origArgs = m[3].strip

        # replace ridiculous syntax
        args = origArgs.gsub(/(\w+) \(\*(.*?)\)\(([^\)]*)\)/) do |m|
          type, name = $1, $2
          cast = $3.gsub(',', '###')
          "#{type}(*)(#{cast}) #{name}" 
        end

        args = args.split(',').map do |arg|
          argarry = arg.split(' ')
          var = argarry.pop
          type = argarry.join(' ').gsub('###', ',') + ' '

          ## split pointers off end of type or beg of name
          var.gsub!('*') do |m|
            type += '*'
            ''
          end
          desc = ''
          comments = comments.gsub(/\@param #{Regexp.escape(var)} ([^@]*)/m) do |m|
            desc = $1.gsub("\n", ' ').gsub("\t", ' ').strip
            ''
          end
          ## TODO: parse comments to extract data about args
          {:type => type.strip, :name => var, :comment => desc}
        end

        sig = args.map do |arg|
          arg[:type].to_s
        end.join('::')

        return_comment = ''
        comments.gsub!(/\@return ([^@]*)/m) do |m|
          return_comment = $1.gsub("\n", ' ').gsub("\t", ' ').strip
          ''
        end

        comments = strip_block(comments)
        comment_lines = comments.split("\n\n")

        desc = ''
        if comments.size > 0
          desc = comment_lines.shift.split("\n").map { |e| e.strip }.join(' ')
          comments = comment_lines.join("\n\n").strip
        end

        next if fun == 'defined'
        @data[:functions][fun] = {
          :description => desc,
          :return => {:type => ret, :comment => return_comment},
          :args => args,
          :argline => origArgs,
          :file => file,
          :line => block[:line],
          :lineto => block[:lineto],
          :comments => comments,
          :sig => sig,
          :rawComments => rawComments
        }
        funcs << fun
      end
    end
    funcs
  end

  # TODO: rolled this back, want to strip the first few spaces, not everything
  def strip_block(block)
    block.strip
  end

  def mkdir_temp
    tf = Tempfile.new('docurium')
    tpath = tf.path
    tf.unlink
    FileUtils.mkdir_p(tpath)
    tpath
  end

  def mkfile_temp
    tf = Tempfile.new('docurium-index')
    tpath = tf.path
    tf.unlink
    tpath
  end

  def copy_site(outdir)
    here = File.expand_path(File.dirname(__FILE__))
    FileUtils.mkdir_p(outdir)
    Dir.chdir(outdir) do
      FileUtils.cp_r(File.join(here, '..', 'site', '.'), '.') 
    end
  end

  def write_dir
    out "Writing to directory #{output_dir}"
    out "Done!"
  end

  def out(text)
    puts text
  end
end
