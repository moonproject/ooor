require 'active_support/core_ext/hash/indifferent_access'
require 'ooor/session'

module Ooor
  autoload :SecureRandom, 'securerandom'
  # The SessionHandler allows to retrieve a session with its loaded proxies to OpenERP
  class SessionHandler

    def noweb_session_spec(config)
      "#{config[:url]}-#{config[:database]}-#{config[:username]}"
    end

    # gives a hash config from a connection string or a yaml file, injects default values
    def format_config(config)
      if config.is_a?(String) && config.end_with?('.yml')
        env = defined?(Rails.env) ? Rails.env : nil
        config = load_config_file(config, env)
      end
      if config.is_a?(String)
        cs = config
        config = {}
      elsif config[:ooor_url]
        cs = config[:ooor_url]
      elsif ENV['OOOR_URL']
        cs = ENV['OOOR_URL'].dup()
      end
      config.merge!(parse_connection_string(cs)) if cs

      defaults = {
        url: 'http://localhost:8069',
        username: 'admin',
      }
      defaults[:password] = ENV['OOOR_PASSWORD'] if ENV['OOOR_PASSWORD']
      defaults[:username] = ENV['OOOR_USERNAME'] if ENV['OOOR_USERNAME']
      defaults[:database] = ENV['OOOR_DATABASE'] if ENV['OOOR_DATABASE']
      defaults.merge(config)
		end

    def retrieve_session(config, id=nil, web_session={})
      id ||= SecureRandom.hex(16)
      if id == :noweb
        spec = noweb_session_spec(config)
      else
        spec = id
      end

      s = sessions[spec]
      # reload session or create a new one if no matching session found
      if config[:reload] || !s
        config = Ooor.default_config.merge(config) if Ooor.default_config.is_a? Hash
        Ooor::Session.new(config, web_session, id)

      # found but config mismatch still
      elsif noweb_session_spec(s.config) != noweb_session_spec(config)
        config = Ooor.default_config.merge(config) if Ooor.default_config.is_a? Hash
        Ooor::Session.new(config, web_session, id)

      # matching session, update web_session of it eventually
      else
        s.tap {|s| s.web_session.merge!(web_session)} #TODO merge config also?
      end
    end

    def register_session(session)
      if session.config[:session_sharing]
        spec = session.web_session[:session_id]
      elsif session.id != :noweb
        spec = session.id
      else
        spec = noweb_session_spec(session.config)
      end
      set_web_session(spec, session.web_session)
      sessions[spec] = session
    end

    def reset!
      @sessions = {}
      @connections = {}
    end

    def get_web_session(key)
      Ooor.cache.read(key)
    end

    def set_web_session(key, web_session)
      Ooor.cache.write(key, web_session)
    end

    def sessions; @sessions ||= {}; end
    def connections; @connections ||= {}; end


    private

    def load_config_file(config_file=nil, env=nil)
      config_file ||= defined?(Rails.root) && "#{Rails.root}/config/ooor.yml" || 'ooor.yml'
      config_parsed = ::YAML.load(ERB.new(File.new(config_file).read).result)
      HashWithIndifferentAccess.new(config_parsed)[env || 'development']
    rescue SystemCallError
      Ooor.logger.error """failed to load OOOR yaml configuration file.
         make sure your app has a #{config_file} file correctly set up
         if not, just copy/paste the default ooor.yml file from the OOOR Gem
         to #{Rails.root}/config/ooor.yml and customize it properly\n\n"""
      {}
    end

    def parse_connection_string(cs)
      if cs.start_with?('ooor://') && ! cs.index('@')
        cs.sub!(/^ooor:\/\//, '@')
      end

      cs.sub!(/^http:\/\//, '')
      cs.sub!(/^ooor:/, '')
      cs.sub!(/^ooor:/, '')
      cs.sub!('//', '')
      if cs.index('ssl=true')
        ssl = true
        cs.gsub!('?ssl=true', '').gsub!('ssl=true', '')
      end
      if cs.index(' -s')
        ssl = true
        cs.gsub!(' -s', '')
      end

      if cs.index('@')
        parts = cs.split('@')
        right = parts[1]
        left = parts[0]
        if right.index('/')
          parts = right.split('/')
          database = parts[1]
          host, port = parse_host_port(parts[0])
        else
          host, port = parse_host_port(right)
        end

        if left.index(':')
          user_pwd = left.split(':')
          username = user_pwd[0]
          password = user_pwd[1]
        else
          if left.index('.') && !database
            username = left.split('.')[0]
            database = left.split('.')[1]
          else
            username = left
          end
        end
      else
        host, port = parse_host_port(cs)
      end

      host ||= 'localhost'
      port ||= 8069
      if port == 443
      	ssl = true
      end
      username = 'admin' if username.blank?
      {
        url: "#{ssl ? 'https' : 'http'}://#{host}:#{port}",
        username: username,
        database: database,
        password: password,
      }.select { |_, value| !value.nil? } # .compact() on Rails > 4
    end

    def parse_host_port(host_port)
      if host_port.index(':')
        host_port = host_port.split(':')
        host = host_port[0]
        port = host_port[1].to_i
      else
        host = host_port
        port = 80
      end
      return host, port
    end

  end
end
