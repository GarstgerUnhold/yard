module YARD
  # This class maintains all system-wide configuration for YARD and handles
  # the loading of plugins. To access options call {options}, and to load
  # a plugin use {load_plugin}. All other public methods are used by YARD
  # during load time.
  # 
  # == User Configuration Files
  # 
  # Persistent user configuration files can be stored in the file 
  # +~/.yard/config+, which is read when YARD first loads. The file should
  # be formatted as YAML, and should contain a map of keys and values.
  # 
  # Although you can specify any key-value mapping in the configuration file,
  # YARD defines special keys specified in {DEFAULT_CONFIG_OPTIONS}.
  # 
  # An example of a configuration file is listed below:
  # 
  #     !!!yaml
  #     load_plugins: true # Auto-load plugins when YARD starts
  #     ignored_plugins:
  #       - yard-broken
  #       - broken2 # yard- prefix not necessary
  #     autoload_plugins:
  #       - yard-rspec
  # 
  # == Automatic Loading of Plugins
  # 
  # YARD 0.6.2 will no longer automatically load all plugins by default. This 
  # option can be reset by setting 'load_plugins' to true in the configuration 
  # file. In addition, you can specify a set of specific plugins to load on 
  # load through the 'autoload_plugins' list setting. This setting is 
  # independent of the 'load_plugins' value and will always be processed.
  # 
  # == Ignored Plugins File
  # 
  # YARD 0.5 and below used a +~/.yard/ignored_plugins+ file to specify
  # plugins to be ignored at load time. Ignored plugins in 0.6.2 and above
  # should now be specified in the main configuration file, though YARD
  # will support the +ignored_plugins+ file until 0.7.x.
  # 
  # @since 0.6.2
  # @see options
  class Config
    class << self
      # The system-wide configuration options for YARD
      # @return [SymbolHash] a map a key-value pair settings.
      # @see DEFAULT_CONFIG_OPTIONS
      attr_accessor :options
    end

    # The location where YARD stores user-specific settings
    CONFIG_DIR = File.expand_path('~/.yard')
    
    # The main configuration YAML file.
    CONFIG_FILE = File.join(CONFIG_DIR, 'config')
    
    # File listing all ignored plugins 
    # @deprecated Set `ignored_plugins` in the {CONFIG_FILE} instead.
    IGNORED_PLUGINS = File.join(CONFIG_DIR, 'ignored_plugins')
    
    # Default configuration options
    DEFAULT_CONFIG_OPTIONS = {
      :load_plugins => false,   # Whether to load plugins automatically with YARD
      :ignored_plugins => [],   # A list of ignored plugins by name
      :autoload_plugins => []   # A list of plugins to be automatically loaded
    }
    
    YARD_PLUGIN_PREFIX = /^yard[-_]/
    
    # Loads settings from {CONFIG_FILE}. This method is called by YARD at
    # load time and should not be called by the user.
    # @return [void]
    def self.load
      self.options = SymbolHash.new(false)
      options.update(DEFAULT_CONFIG_OPTIONS)
      options.update(read_config_file)
      add_ignored_plugins_file
      translate_plugin_names
      load_plugins
    end
    
    # Loads gems that match the name 'yard-*' (recommended) or 'yard_*' except
    # those listed in +~/.yard/ignored_plugins+. This is called immediately 
    # after YARD is loaded to allow plugin support.
    # 
    # @return [Boolean] true if all plugins loaded successfully, false otherwise.
    def self.load_plugins
      load_gem_plugins &&
        load_autoload_plugins &&
        load_commandline_plugins ? true : false
    end
    
    # Loads an individual plugin by name. It is not necessary to include the
    # +yard-+ plugin prefix here.
    # 
    # @param [String] name the name of the plugin (with or without +yard-+ prefix)
    # @return [Boolean] whether the plugin was successfully loaded
    def self.load_plugin(name)
      name = translate_plugin_name(name)
      return false if options[:ignored_plugins].include?(name)
      return false if name =~ /^yard-doc-/
      log.debug "Loading plugin '#{name}'..."
      require name
      true
    rescue LoadError => e
      load_plugin_failed(name, e)
    end
    
    private
    
    # Load gem plugins if :load_plugins is true
    def self.load_gem_plugins
      return true unless options[:load_plugins]
      require 'rubygems'
      result = true
      Gem.source_index.find_name('').each do |gem|
        begin
          next true unless gem.name =~ YARD_PLUGIN_PREFIX
          load_plugin(gem.name)
        rescue Gem::LoadError => e
          tmp = load_plugin_failed(gem.name, e)
          result = tmp if !tmp
        end
      end
      result
    rescue LoadError
      log.debug "RubyGems is not present, skipping plugin loading"
      false
    end
    
    # Load plugins set in :autoload_plugins
    def self.load_autoload_plugins
      options[:autoload_plugins].each {|name| load_plugin(name) }
    end
    
    # Load plugins from ARGV arguments
    def self.load_commandline_plugins
      arguments.each_with_index do |arg, i|
        next unless arg == '--plugin'
        load_plugin(arguments[i+1])
      end
    end
    
    # Print a warning if the plugin failed to load
    # @return [false]
    def self.load_plugin_failed(name, exception)
      log.warn "Error loading plugin '#{name}'"
      log.backtrace(exception)
      false
    end
    
    # Legacy support for {IGNORED_PLUGINS}
    def self.add_ignored_plugins_file
      if File.file?(IGNORED_PLUGINS)
        options[:ignored_plugins] += File.read(IGNORED_PLUGINS).split(/\s+/)
      end
    end
    
    # Translates plugin names to add yard- prefix.
    def self.translate_plugin_names
      options[:ignored_plugins].map! {|name| translate_plugin_name(name) }
      options[:autoload_plugins].map! {|name| translate_plugin_name(name) }
    end

    # Loads the YAML configuration file into memory
    # @return [Hash] the contents of the YAML file from disk
    # @see CONFIG_FILE
    def self.read_config_file
      if File.file?(CONFIG_FILE)
        require 'yaml'
        YAML.load_file(CONFIG_FILE)
      else
        {}
      end
    end
    
    # Sanitizes and normalizes a plugin name to include the 'yard-' prefix.
    # @param [String] name the plugin name
    # @return [String] the sanitized and normalized plugin name.
    def self.translate_plugin_name(name)
      name = name.gsub('/', '') # Security sanitization
      name = "yard-" + name unless name =~ YARD_PLUGIN_PREFIX
      name
    end
    
    # Returns ARGV. Used for test stubbing only.
    def self.arguments; ARGV end
  end
  
  Config.options = Config::DEFAULT_CONFIG_OPTIONS
end
