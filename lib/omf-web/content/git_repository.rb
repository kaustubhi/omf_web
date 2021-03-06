
#require 'base64'
require 'grit'
require 'find'
require 'omf_common/lobject'
require 'omf_web'
require 'omf-web/content/content_proxy'
require 'omf-web/content/repository'

module OMF::Web

  # This class provides an interface to a GIT repository
  # It retrieves, archives and versions content.
  #
  class GitContentRepository < ContentRepository

    # @@git_repositories = {}
#
    # # Return the repository which is referenced to by elements in 'opts'.
    # #
    # #
    # def self.[](name)
      # unless repo = @@git_repositories[name.to_sym]
        # raise "Unknown git repo '#{name}'"
      # end
      # repo
    # end

    # Register an existing GIT repo to the system. It will be
    # consulted for all content url's strarting with
    # 'git:_top_dir_:'. If 'is_primary' is set to true, it will
    # become the default repo for all newly created content
    # in this app.
    #
    # def self.register_git_repo(name, top_dir, is_primary = false)
      # name = name.to_sym
      # if @@git_repositories[name]
        # warn "Ignoring repeated registration of git rep '#{name}'"
        # return
      # end
      # repo = @@git_repositories[name] = GitContentRepository.new(name, top_dir)
      # if is_primary
        # @@primary_repository = repo
      # end
    # end

    # def self.read_content(url, opts)
      # unless (a = url.split(':')).length == 3
        # raise "Expected 'git:some_name:some_path', but got '#{url}'"
      # end
      # git, name, path = a
      # unless (repo = @@repositories['git:' + name])
        # raise "Unknown git repository '#{name}'"
      # end
      # repo.read(path)
    # end

    attr_reader :name, :top_dir

    def initialize(name, opts)
      super
      @repo = Grit::Repo.new(@top_dir)
      @url_prefix = "git:#{@name}:"
    end

    #
    # Create a URL for a file with 'path' in.
    # If 'strictly_new' is true, returns nil if 'path' already exists.
    #
    # def create_url(path, strictly_new = true)
      # return "git:"
      # # TODO: Need to add code to select proper repository
      # return GitContentRepository.create_url(path, strictly_new)
    # end


    # Load content described by either a hash or a straightforward path
    # and return a 'ContentProxy' holding it.
    #
    # If descr[:strictly_new] is true, return nil if file for which proxy is requested
    # already exists.
    #
    # @return: Content proxy
    #
    def create_content_proxy_for(content_descr)
      path = _get_path(content_descr)
      # TODO: Make sure that key is really unique across multiple repositories
      url = @url_prefix + path
      key = Digest::MD5.hexdigest(url)
      descr = {}
      descr[:url] = url
      descr[:url_key] = key
      descr[:path] = path
      descr[:name] = url # Should be something human digestable
      if (descr[:strictly_new])
        Dir.chdir(@top_dir) do
          return nil if File.exist?(path)
        end
      end
      proxy = ContentProxy.create(descr, self)
      return proxy
    end

    def write(content_descr, content, message)
      path = _get_path(content_descr)
      Dir.chdir(@top_dir) do
        unless File.writable?(path)
          raise "Cannot write to file '#{path}'"
        end
        f = File.open(path, 'w')
        f.write(content)
        f.close

        @repo.add(path)
        # TODO: Should set info about committing user which should be in thread context
        @repo.commit_index(message || 'no message')
      end
    end

    # Return a URL for a path in this repo
    #
    def get_url_for_path(path)
      @url_prefix + path
    end



    #
    # Return an array of file names which are in the repository and
    # match 'search_pattern'
    #
    def find_files(search_pattern, opts = {})
      search_pattern = Regexp.new(search_pattern)
      tree = @repo.tree
      res = []
      fs = _find_files(search_pattern, tree, nil, res)

      if (mt = opts[:mime_type])
        fs = fs.select { |f| f[:mime_type] == mt }
      end
      fs
    end

    def _find_files(search_pattern, tree, dir_path, res)
      tree.contents.each do |e|
        d = e.name
        long_name = dir_path ? "#{dir_path}/#{d}" : d

        if e.is_a? Grit::Tree
          _find_files(search_pattern, e, long_name, res)
        else
          if long_name.match(search_pattern)
            mt = mime_type_for_file(e.name)
            #path = @url_prefix + long_name
            path = long_name
            res << {path: path, url: get_url_for_path(path), name: e.name,
                    mime_type: mt,
                    #:id => Base64.encode64(long_name).gsub("\n", ''),
                    size: e.size, blob: e.id}
          end
          # name = e.name
          # if File.fnmatch(search_pattern, long_name)
            # res << long_name
          # end
        end
      end
      res
    end

    def _get_path(content_descr)
      if content_descr.is_a? String
        path = content_descr.to_s
        if path.start_with? 'git:'
          path = path.split(':')[2]
        end
      elsif content_descr.is_a? Hash
        descr = content_descr
        if (url = descr[:url])
          path = url.split(':')[2] # git:repo_name:path
        else
          path = descr[:path]
        end
        unless path
          raise "Missing 'path' or 'url' in content description (#{descr.inspect})"
        end
        path = path.to_s
      else
        raise "Unsupported type '#{content_descr.class}'"
      end
      unless path
        raise "Can't find path information in '#{content_descr.inspect}'"
      end
      return path
    end

  end # class
end # module