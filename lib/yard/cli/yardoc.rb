require 'digest/sha1'
require 'fileutils'

module YARD
  module CLI
    class Yardoc < Base
      # The configuration filename to load extra options from
      DEFAULT_YARDOPTS_FILE = ".yardopts"
      
      # @return [Hash] the hash of options passed to the template.
      # @see Templates::Engine#render
      attr_reader :options
      
      # @return [Array<String>] list of Ruby source files to process
      attr_accessor :files
      
      # @return [Boolean] whether to reparse the source files even if the 
      #   .yardoc already exists.
      attr_accessor :reload
      
      # @return [Boolean] whether to generate output
      attr_accessor :generate
      
      # The options file name (defaults to {DEFAULT_YARDOPTS_FILE})
      # @return [String] the filename to load extra options from
      attr_accessor :options_file
      
      # Helper method to create an instance and run the utility
      # @see #run
      def self.run(*args) new.run(*args) end
        
      # Creates a new instance of the commandline utility
      def initialize
        @options = SymbolHash.new(false)
        @options.update(
          :format => :html, 
          :template => :default, 
          :markup => :rdoc,
          :serializer => YARD::Serializers::FileSystemSerializer.new,
          :default_return => "Object",
          :hide_void_return => false,
          :no_highlight => false, 
          :files => [],
          :visibilities => [:public],
          :verifier => nil
        )
        @files = []
        @reload = true
        @generate = true
        @options_file = DEFAULT_YARDOPTS_FILE
      end
      
      # Runs the commandline utility, parsing arguments and generating
      # output if set.
      # 
      # @param [Array<String>] args the list of arguments
      # @return [void] 
      def run(*args)
        args += support_rdoc_document_file!
        optparse(*yardopts)
        optparse(*args)
        Registry.load(files, reload)
        
        if generate
          Templates::Engine.generate(all_objects, options)
        end
        
        true
      end

      # The list of all objects to process. Override this method to change
      # which objects YARD should generate documentation for.
      # 
      # @return [Array<CodeObjects::Base>] a list of code objects to process
      def all_objects
        Registry.all(:root, :module, :class)
      end
      
      # Parses the .yardopts file for default yard options
      # @return [void] 
      def yardopts
        IO.read(options_file).shell_split
      rescue Errno::ENOENT
        []
      end
      
      private
      
      # Reads a .document file in the directory to get source file globs
      # @return [void] 
      def support_rdoc_document_file!
        IO.read(".document").gsub(/^[ \t]*#.+/m, '').split(/\s+/)
      rescue Errno::ENOENT
        []
      end
      
      # Adds a set of extra documentation files to be processed
      # @param [Array<String>] files the set of documentation files
      def add_extra_files(*files)
        files.map! {|f| f.include?("*") ? Dir.glob(f) : f }.flatten!
        files.each do |file|
          raise Errno::ENOENT, "Could not find extra file: #{file}" unless File.file?(file)
          options[:files] << file
        end
      end
      
      # Parses the file arguments into Ruby files and extra files, which are
      # separated by a '-' element.
      # 
      # @example Parses a set of Ruby source files
      #   parse_files %w(file1 file2 file3)
      # @example Parses a set of Ruby files with a separator and extra files
      #   parse_files %w(file1 file2 - extrafile1 extrafile2)
      # @param [Array<String>] files the list of files to parse
      # @return [void] 
      def parse_files(*files)
        self.files = []
        seen_extra_files_marker = false
        
        files.each do |file|
          if file == "-"
            seen_extra_files_marker = true
            next
          end
          
          if seen_extra_files_marker
            add_extra_files(file)
          else
            self.files << file
          end
        end
      end
      
      # Builds .yardoc files for all non-existing gems
      def build_gems
        require 'rubygems'
        Gem.source_index.find_name('').each do |spec|
          Registry.clear
          reload = true
          yfile = Registry.yardoc_file_for_gem(spec.name, ">= 0", true)
          if !File.directory?(yfile)
            Dir.chdir(spec.full_gem_path)
            log.info "Building yardoc index for gem: #{spec.full_name}"
            Yardoc.run('-n', '-b', yfile)
            reload = false
          end
        end
        exit(0)
      end
      
      # Parses commandline options.
      # @param [Array<String>] args each tokenized argument
      def optparse(*args)
        query_expressions = []
        merge = false
        serialopts = SymbolHash.new
        
        opts = OptionParser.new
        opts.banner = "Usage: yardoc [options] [source_files [- extra_files]]"

        opts.separator "(if a list of source files is omitted, lib/**/*.rb ext/**/*.c is used.)"
        opts.separator ""
        opts.separator "Example: yardoc -o documentation/ - FAQ LICENSE"
        opts.separator "  The above example outputs documentation for files in"
        opts.separator "  lib/**/*.rb to documentation/ including the extra files"
        opts.separator "  FAQ and LICENSE."
        opts.separator ""
        opts.separator "A base set of options can be specified by adding a .yardopts"
        opts.separator "file to your base path containing all extra options separated"
        opts.separator "by whitespace."
        opts.separator ""
        opts.separator "General Options:"

        opts.on('-c', '--use-cache [FILE]', 
                'Use the cached .yardoc db to generate documentation. (defaults to no cache)') do |file|
          YARD::Registry.yardoc_file = file if file
          self.reload = false
        end
        
        opts.on('-b', '--db FILE', 'Use a specified .yardoc db to load from or save to. (defaults to .yardoc)') do |yfile|
          YARD::Registry.yardoc_file = yfile
        end
        
        opts.on('--merge', 'Merged the output of .yardoc with parsed contents') do
          merge = true
        end
        
        opts.on('-n', '--no-output', 'Only generate .yardoc database, no documentation.') do
          self.generate = false
        end
        
        opts.on('-e', '--load FILE', 'A Ruby script to load before the source tree is parsed.') do |file|
          if !require(file.gsub(/\.rb$/, ''))
            log.error "The file `#{file}' was already loaded, perhaps you need to specify the absolute path to avoid name collisions."
            exit
          end
        end
        
        opts.on('--legacy', 'Use old style parser and handlers. Unavailable under Ruby 1.8.x') do
          YARD::Parser::SourceParser.parser_type = :ruby18
        end
        
        opts.on('--build-gems', 'Builds .yardoc files for all gems (implies -n)') do
          build_gems
        end

        opts.separator ""
        opts.separator "Output options:"
  
        opts.on('--no-public', "Don't show public methods. (default shows public)") do 
          options[:visibilities].delete(:public)
        end

        opts.on('--protected', "Show or don't show protected methods. (default hides protected)") do
          options[:visibilities].push(:protected)
        end

        opts.on('--private', "Show or don't show private methods. (default hides private)") do 
          options[:visibilities].push(:private) 
        end
        
        opts.on('--no-private', "Hide objects with @private tag") do
          query_expressions << '!@private'
        end

        opts.on('--no-highlight', "Don't highlight code in docs as Ruby.") do 
          options[:no_highlight] = true
        end
        
        opts.on('--default-return TYPE', "Shown if method has no return type. Defaults to 'Object'") do |type|
          options[:default_return] = type
        end
        
        opts.on('--hide-void-return', "Hides return types specified as 'void'. Default is shown.") do
          options[:hide_void_return] = true
        end
        
        opts.on('--query QUERY', "Only show objects that match a specific query") do |query|
          query_expressions << query.taint
        end
        
        opts.on('--title TITLE', 'Add a specific title to HTML documents') do |title|
          options[:title] = title
        end

        opts.on('-r', '--readme FILE', '--main FILE', 'The readme file used as the title page of documentation.') do |readme|
          raise Errno::ENOENT, readme unless File.file?(readme)
          options[:readme] = readme
        end
        
        opts.on('--files FILE1,FILE2,...', 'Any extra comma separated static files to be included (eg. FAQ)') do |files|
          add_extra_files *files.split(",")
        end

        opts.on('-m', '--markup MARKUP', 
                'Markup style used in documentation, like textile, markdown or rdoc. (defaults to rdoc)') do |markup|
          options[:markup] = markup.to_sym
        end

        opts.on('-M', '--markup-provider MARKUP_PROVIDER', 
                'Overrides the library used to process markup formatting (specify the gem name)') do |markup_provider|
          options[:markup_provider] = markup_provider.to_sym
        end
        
        opts.on('-o', '--output-dir PATH', 
                'The output directory. (defaults to ./doc)') do |dir|
          options[:serializer] = nil
          serialopts[:basepath] = dir
        end

        opts.on('-t', '--template TEMPLATE', 
                'The template to use. (defaults to "default")') do |template|
          options[:template] = template.to_sym
        end

        opts.on('-p', '--template-path PATH', 
                'The template path to look for templates in. (used with -t).') do |path|
          YARD::Templates::Engine.register_template_path(path)
        end
        
        opts.on('-f', '--format FORMAT', 
                'The output format for the template. (defaults to html)') do |format|
          options[:format] = format.to_sym
        end

        common_options(opts)
        
        begin
          opts.parse!(args)
        rescue OptionParser::InvalidOption => e
          STDERR.puts e.message
          STDERR << "\n" << opts
          exit
        end
        
        # Last minute modifications
        Registry.load_yardoc if merge
        parse_files(*args) unless args.empty?
        self.files = ['lib/**/*.rb', 'ext/**/*.c'] if self.files.empty?
        options[:verifier] = Verifier.new(*query_expressions) unless query_expressions.empty?
        options[:visibilities].uniq!
        options[:serializer] ||= Serializers::FileSystemSerializer.new(serialopts)
        options[:readme] ||= Dir.glob('README*').first
      end
    end
  end
end
