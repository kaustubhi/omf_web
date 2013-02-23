
require 'omf_common/lobject'
require 'rack'
require 'omf-web/session_store'

      
module OMF::Web::Rack   
  # This rack module maintains a session cookie and 
  # redirects any requests to protected pages to a 
  # 'login' page at the beginning of a session
  #
  # Calls to the class methods are resolved inthe context
  # of a Session using 'OMF::Web::SessionStore'
  #
  class SessionAuthenticator < OMF::Common::LObject
    
    # Returns true if this Rack module has been instantiated
    # in the current Rack stack.
    #
    def self.active?
      @@active
    end

    # Return true if the session is authenticated
    #
    def self.authenticated?
      debug "AUTH: #{self[:authenticated] == true}"
      self[:authenticated] == true
    end

    # Calling this method will authenticate the current session
    #
    def self.authenticate
      self[:authenticated] = true
      self[:valid_until] = Time.now + @@expire_after
    end
    
    # Logging out will un-authenticate this session
    #
    def self.logout
      debug "LOGOUT"
      self[:authenticated] = false
    end

    # DO NOT CALL DIRECTLY
    #
    def self.[](key)
      OMF::Web::SessionStore[key, :authenticator]
    end
    
    # DO NOT CALL DIRECTLY
    #
    def self.[]=(key, value)
      OMF::Web::SessionStore[key, :authenticator] = value
    end

    @@active = false
    # Expire authenticated session after being idle for that many seconds
    @@expire_after = 2592000
    
    #
    # opts -
    #   :login_url - URL to redirect if session is not authenticated  
    #   :no_session - Array of regexp on 'path_info' which do not require an authenticated session
    #   :expire_after - Idle time in sec after which to expire a session
    #
    def initialize(app, opts = {})
      @app = app
      @opts = opts
      @opts[:no_session] = (@opts[:no_session] || []).map { |s| Regexp.new(s) }
      if @opts[:expire_after]
        @@expire_after = @opts[:expire_after]
      end
      @@active = true
    end
    
    
    def call(env)
      #puts env.keys.inspect
      req = ::Rack::Request.new(env)
      sid = nil
      path_info = req.path_info
      #puts "REQUEST: #{path_info}"
      unless @opts[:no_session].find {|rx| rx.match(path_info) }
        sid = req.cookies['sid'] || "s#{(rand * 10000000).to_i}_#{(rand * 10000000).to_i}"
        debug "Setting session for '#{req.path_info}' to '#{sid}'"
        Thread.current["sessionID"] = sid
        # If 'login_url' is defined, check if this session is authenticated
        login_url = @opts[:login_url] 
        if login_url && login_url != req.path_info
          if authenticated = self.class.authenticated?
            # Check if it hasn't timed out
            if self.class[:valid_until] < Time.now
              debug "Session '#{sid}' expired"
              authenticated = false
            end    
          end
          unless authenticated
            return [301, {'Location' => login_url, "Content-Type" => ""}, ['Login first']]
          end
        end
        self.class[:valid_until] = Time.now + @@expire_after
      end
            
      status, headers, body = @app.call(env)
      if sid
        headers['Set-Cookie'] = "sid=#{sid}"  ##: name2=value2; Expires=Wed, 09-Jun-2021 ]
      end
      [status, headers, body]      
    end
  end # class
  
end # module


      
        
