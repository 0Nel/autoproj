module Autoproj
    class UserError < RuntimeError; end

    # Returns true if +path+ is part of an autoproj installation
    def self.in_autoproj_installation?(path)
        root_dir(File.expand_path(path))
        true
    rescue UserError
        false
    end

    # Returns the root directory of the current autoproj installation.
    #
    # If the current directory is not in an autoproj installation,
    # raises UserError.
    def self.root_dir(dir = Dir.pwd)
        while dir != "/" && !File.directory?(File.join(dir, "autoproj"))
            dir = File.dirname(dir)
        end
        if dir == "/"
            raise UserError, "not in a Autoproj installation"
        end
        dir
    end

    # Returns the configuration directory for this autoproj installation.
    #
    # If the current directory is not in an autoproj installation,
    # raises UserError.
    def self.config_dir
        File.join(root_dir, "autoproj")
    end

    class << self
        # The directory in which packages will be installed.
        #
        # If it is a relative path, it is relative to the root dir of the
        # installation.
        #
        # The default is "install"
        attr_reader :prefix

        # Change the value of 'prefix'
        def prefix=(new_path)
            @prefix = new_path
            Autoproj.change_option('prefix', new_path, true)
        end
    end
    @prefix = "install"

    # Returns the build directory (prefix) for this autoproj installation.
    #
    # If the current directory is not in an autoproj installation, raises
    # UserError.
    def self.build_dir
        File.expand_path(Autoproj.prefix, root_dir)
    end

    # Returns the path to the provided configuration file.
    #
    # If the current directory is not in an autoproj installation, raises
    # UserError.
    def self.config_file(file)
        File.join(config_dir, file)
    end

    # Run the provided command as user
    def self.run_as_user(*args)
        if !system(*args)
            raise "failed to run #{args.join(" ")}"
        end
    end

    # Run the provided command as root, using sudo to gain root access
    def self.run_as_root(*args)
        if !system('sudo', *args)
            raise "failed to run #{args.join(" ")} as root"
        end
    end

    # Return the directory in which remote package set definition should be
    # checked out
    def self.remotes_dir
        File.join(root_dir, ".remotes")
    end

    # Return the directory in which RubyGems package should be installed
    def self.gem_home
        ENV['AUTOPROJ_GEM_HOME'] || File.join(root_dir, ".gems")
    end

    # Find the given program in PATH. It raises ArgumentError if the program
    # can't be found
    def self.find_in_path(name)
        result = ENV['PATH'].split(':').find { |dir| File.file?(File.join(dir, name)) }
        if !result
            raise ArgumentError, "#{name} can not be found in PATH"
        end
        File.join(result, name)
    end

    # Initializes the environment variables to a "sane default"
    #
    # Use this in autoproj/init.rb to make sure that the environment will not
    # get polluted during the build.
    def self.set_initial_env
        Autoproj.env_set 'RUBYOPT', "-rubygems"
        Autoproj.env_set 'GEM_HOME', Autoproj.gem_home
        Autoproj.env_set_path 'PATH', "#{Autoproj.gem_home}/bin", "/usr/local/bin", "/usr/bin", "/bin"
        Autoproj.env_set 'PKG_CONFIG_PATH'
        Autoproj.env_set 'RUBYLIB'
        Autoproj.env_set 'LD_LIBRARY_PATH'
    end

    class << self
        attr_writer :shell_helpers
        def shell_helpers?; !!@shell_helpers end
    end
    @shell_helpers = true

    # Create the env.sh script in +subdir+. In general, +subdir+ should be nil.
    def self.export_env_sh(subdir = nil)
        filename = if subdir
                       File.join(Autoproj.root_dir, subdir, "env.sh")
                   else
                       File.join(Autoproj.root_dir, "env.sh")
                   end

        File.open(filename, "w") do |io|
            variables = []
            Autobuild.environment.each do |name, value|
                variables << name
                shell_line = "#{name}=#{value.join(":")}"
                if Autoproj.env_inherit?(name)
                    if value.empty?
                        next
                    else
                        shell_line << ":$#{name}"
                    end
                end
                io.puts shell_line
            end
            variables.each do |var|
                io.puts "export #{var}"
            end

            shell_dir = File.expand_path(File.join("..", "..", "shell"), File.dirname(__FILE__))
            if Autoproj.shell_helpers? && shell = ENV['SHELL']
                shell_kind = File.basename(shell)
                if shell_kind =~ /^\w+$/
                    shell_file = File.join(shell_dir, "autoproj_#{shell_kind}")
                    if File.exists?(shell_file)
                        Autoproj.progress
                        Autoproj.progress "autodetected the shell to be #{shell_kind}, sourcing autoproj shell helpers"
                        Autoproj.progress "add \"Autoproj.shell_helpers = false\" in autoproj/init.rb to disable"
                        io.puts "source \"#{shell_file}\""
                    end
                end
            end
        end
    end

    # Load a definition file given at +path+. +source+ is the package set from
    # which the file is taken.
    #
    # If any error is detected, the backtrace will be filtered so that it is
    # easier to understand by the user. Moreover, if +source+ is non-nil, the
    # package set name will be mentionned.
    def self.load(source, *path)
        path = File.join(*path)
        Kernel.load path
    rescue Interrupt
        raise
    rescue Exception => e
        Autoproj.filter_load_exception(e, source, path)
    end

    # Same as #load, but runs only if the file exists.
    def self.load_if_present(source, *path)
        path = File.join(*path)
        if File.file?(path)
            self.load(source, *path)
        end
    end

    # Look into +dir+, searching for shared libraries. For each library, display
    # a warning message if this library has undefined symbols.
    def self.validate_solib_dependencies(dir, exclude_paths = [])
        Find.find(File.expand_path(dir)) do |name|
            next unless name =~ /\.so$/
            next if exclude_paths.find { |p| name =~ p }

            output = `ldd -r #{name} 2>&1`
            if output =~ /undefined symbol/
                Autoproj.progress("  WARN: #{name} has undefined symbols", :magenta)
            end
        end
    end
end

