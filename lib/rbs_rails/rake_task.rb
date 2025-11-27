require 'rake'
require 'rake/tasklib'

module RbsRails
  class RakeTask < Rake::TaskLib
    # @rbs!
    #   interface _Filter
    #     def call: (Class) -> boolish
    #   end

    attr_accessor :ignore_model_if #: _Filter | nil
    attr_accessor :name #: Symbol
    attr_writer :signature_root_dir #: Pathname?

    # @rbs name: ::Symbol
    # @rbs &block: (RbsRails::RakeTask) -> void
    def initialize(name = :rbs_rails, &block) #: void
      super()

      @name = name
      @signature_root_dir = nil

      block.call(self) if block

      def_generate_rbs_for_models
      def_generate_rbs_for_path_helpers
      def_all
    end

    def def_all #: void
      desc 'Run all tasks of rbs_rails'
      deps = [:"#{name}:generate_rbs_for_models", :"#{name}:generate_rbs_for_path_helpers"]
      task("#{name}:all": deps)
    end

    def def_generate_rbs_for_models #: void
      desc 'Generate RBS files for Active Record models'
      task("#{name}:generate_rbs_for_models": :environment) do
        require 'rbs_rails'

        # Load configuration if available
        load_config_if_exists

        Rails.application.eager_load!

        dep_builder = DependencyBuilder.new

        ::ActiveRecord::Base.descendants.each do |klass|
          next unless RbsRails::ActiveRecord.generatable?(klass)

          # Check both old ignore_model_if and new config
          next if ignore_model_if&.call(klass)
          next if CLI::Configuration.instance.ignored_model?(klass)

          original_path, _line = Object.const_source_location(klass.name) rescue nil

          rbs_relative_path = if original_path && Pathname.new(original_path).fnmatch?("#{Rails.root}/**")
                                Pathname.new(original_path)
                                        .relative_path_from(Rails.root)
                                        .sub_ext('.rbs')
                              else
                                "app/models/#{klass.name.underscore}.rbs"
                              end

          path = signature_root_dir / rbs_relative_path
          path.dirname.mkpath

          sig = RbsRails::ActiveRecord.class_to_rbs(klass, dependencies: dep_builder.deps)
          path.write sig
          dep_builder.done << klass.name
        end

        if dep_rbs = dep_builder.build
          signature_root_dir.join('model_dependencies.rbs').write(dep_rbs)
        end
      end
    end

    def def_generate_rbs_for_path_helpers #: void
      desc 'Generate RBS files for path helpers'
      task("#{name}:generate_rbs_for_path_helpers": :environment) do
        require 'rbs_rails'

        # Load configuration if available
        load_config_if_exists

        out_path = signature_root_dir.join 'path_helpers.rbs'
        out_path.dirname.mkpath
        rbs = RbsRails::PathHelpers.generate
        out_path.write rbs
      end
    end

    private def signature_root_dir #: Pathname
      if @signature_root_dir
        Pathname(@signature_root_dir).tap { |dir| dir.mkpath }
      elsif defined?(RbsRails::CLI::Configuration)
        CLI::Configuration.instance.signature_root_dir.tap { |dir| dir.mkpath }
      else
        (Rails.root / 'sig/rbs_rails').tap { |dir| dir.mkpath }
      end
    end

    private def load_config_if_exists #: void
      if File.exist?(".rbs_rails.rb")
        load ".rbs_rails.rb"
      elsif Rails.root.join("config/rbs_rails.rb").exist?
        load Rails.root.join("config/rbs_rails.rb").to_s
      end
    end
  end
end
