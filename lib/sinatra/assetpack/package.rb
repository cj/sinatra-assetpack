require 'net/http'
require 'uri'

module Sinatra
  module AssetPack
    # A package.
    #
    # == Common usage
    #
    #     package = assets.packages['application.css']
    #
    #     package.files   # List of local files
    #     package.paths   # List of URI paths
    #
    #     package.type    # :css or :js
    #     package.css?
    #     package.js?
    #
    #     package.path    # '/css/application.css' => where to serve the compressed file
    #
    #     package.to_development_html
    #     package.to_production_html
    #
    class Package
      include HtmlHelpers
      include BusterHelpers

      def initialize(assets, name, type, path, filespecs)
        @assets      = assets     # Options instance
        @name        = name       # "application"
        @type        = type       # :js or :css
        @path        = path       # '/js/app.js' -- where to served the compressed file
        @filespecs   = filespecs  # [ '/js/*.js' ]
      end

      attr_reader :type
      attr_reader :path
      attr_reader :filespecs
      attr_reader :name

      # Returns a list of URIs
      def paths_and_files
        list = @assets.glob(@filespecs, :preserve => true)
        list.reject! { |path, file| @assets.ignored?(path) }
        list
      end

      def files
        paths_and_files.values
      end

      def paths
        paths_and_files.keys
      end

      def already_built
        built_locally || built_remotely
      end

      def built_locally
        File.exists?(File.join(@assets.output_path, add_cache_buster(path)) 
      end

      def built_remotely
        uri = URI.join(@assets.production_host, add_cache_buster(path))
        Net::HTTP.start(uri.host, uri.port) do |http| 
          http.head(uri.path).code =~ /(200|304)/
        end
      rescue Exception
        false
      end

      # Return the maximum mtime for all the files in this package
      def mtime
        @mtime ||= BusterHelpers.mtime_for(files)
      end

      # Returns the regex for the route, including cache buster crap.
      def route_regex
        re = @path.gsub(/(.[^.]+)$/) { |ext| "(?:\.[a-f0-9]+)?#{ext}" }
        /^#{re}$/
      end

      def to_development_html(options={})
        paths_and_files.map { |path, file|
          path = add_cache_buster(path, file)  # app.css => app.829378.css
          link_tag(path, options)
        }.join("\n")
      end

      # The URI path of the minified file (with cache buster)
      def production_path
        @production_path ||= add_cache_buster @path, *files
      end

      def to_production_html(options={})
        link_tag production_path, options
      end

      def minify
        engine  = @assets.send(:"#{@type}_compression")
        options = @assets.send(:"#{@type}_compression_options")

        Compressor.compress combined, @type, engine, options
      end

      # The cache hash.
      def hash
        if @assets.app.development?
          "#{name}.#{type}/#{mtime}"
        else
          "#{name}.#{type}"
        end
      end

      def combined
        session = Rack::Test::Session.new(@assets.app)
        paths.map { |path|
          result = session.get(path)
          result.body  if result.status == 200
        }.join("\n")
      end

      def js?()  @type == :js; end
      def css?() @type == :css; end

    private
      def link_tag(file, options={})
        options = {:rel => 'stylesheet'}.merge(options)
        if js?
          "<script src='#{@assets.production_host}#{e file}'#{kv options}></script>"
        elsif css?
          "<link href='#{@assets.production_host}#{e file}'#{kv options} />"
        end
      end
    end
  end
end
