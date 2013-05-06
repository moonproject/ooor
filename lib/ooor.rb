#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2013 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require 'active_support'

module Ooor
  extend ActiveSupport::Autoload
  autoload :Connection

  module ConnectionBehavior
    extend ActiveSupport::Concern
    module ClassMethods
      #meant to be overriden in multi-tenant mode
      def connection(*args)
        a = b 
        default_ooor
      end
    end
  end

  include ConnectionBehavior

  class << self

    attr_accessor :default_ooor, :default_config

    def new(*args)
      Connection.send :new, *args
    end

    #load the custom configuration
    def load_config(config_file=nil, env=nil)
      config_file ||= defined?(Rails.root) && "#{Rails.root}/config/ooor.yml" || 'ooor.yml'
      @config = YAML.load_file(config_file)[env || 'development']
    rescue SystemCallError
      puts """failed to load OOOR yaml configuration file.
         make sure your app has a #{config_file} file correctly set up
         if not, just copy/paste the default ooor.yml file from the OOOR Gem
         to #{Rails.root}/config/ooor.yml and customize it properly\n\n"""
      {}
    end

    def xtend(model_name, &block)
      @extensions ||= {}
      @extensions[model_name] ||= []
      @extensions[model_name] << block
      @extensions
    end

    def extensions
      @extensions ||= {}
    end

  end
end

require 'ooor/railtie' if defined?(Rails)
