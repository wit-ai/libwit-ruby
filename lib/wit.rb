require 'json'
require 'logger'
require 'net/http'
require 'securerandom'

WIT_API_HOST = ENV['WIT_URL'] || 'https://api.wit.ai'
WIT_API_VERSION = ENV['WIT_API_VERSION']  || '20160516'
DEFAULT_MAX_STEPS = 5
LEARN_MORE = 'Learn more at https://wit.ai/docs/quickstart'

class WitException < Exception
end

def req(logger, access_token, meth_class, path, params={}, payload={})
  uri = URI(WIT_API_HOST + path)
  uri.query = URI.encode_www_form(params)

  logger.debug("#{meth_class} #{uri}")

  request = meth_class.new(uri)
  request['authorization'] = 'Bearer ' + access_token
  request['accept'] = 'application/vnd.wit.' + WIT_API_VERSION + '+json'
  request.add_field 'Content-Type', 'application/json'
  request.body = payload.to_json

  Net::HTTP.start(uri.host, uri.port, {:use_ssl => uri.scheme == 'https'}) do |http|
    rsp = http.request(request)
    if rsp.code.to_i != 200
      raise WitException.new("HTTP error code=#{rsp.code}")
    end
    json = JSON.parse(rsp.body)
    if json.has_key?('error')
      raise WitException.new("Wit responded with an error: #{json['error']}")
    end
    logger.debug("#{meth_class} #{uri} #{json}")
    json
  end
end

def validate_actions(logger, actions)
  [:send].each do |action|
    if !actions.has_key?(action)
      logger.warn "The #{action} action is missing. #{LEARN_MORE}"
    end
  end
  actions.each_pair do |k, v|
    if !k.is_a?(Symbol)
      logger.warn "The '#{k}' action name should be a symbol"
    end
    if !(v.respond_to?(:call) && v.lambda?)
      logger.warn "The '#{k}' action should be a lambda function"
    end
    if k == :send && v.arity != 2
      logger.warn "The \'send\' action should take 2 arguments: request and response. #{LEARN_MORE}"
    end
    if k != :send && v.arity != 1
      logger.warn "The '#{k}' action should take 1 argument: request. #{LEARN_MORE}"
    end
  end
  return actions
end

class Wit
  def initialize(opts = {})
    @access_token = opts[:access_token]

    if opts[:logger]
      @logger = opts[:logger]
    end

    if opts[:actions]
      @actions = validate_actions(logger, opts[:actions])
    end

    @_sessions = {}
  end

  def logger
    @logger ||= begin
      x = Logger.new(STDOUT)
      x.level = Logger::INFO
      x
    end
  end

  def message(msg)
    params = {}
    params[:q] = msg unless msg.nil?
    res = req(logger, @access_token, Net::HTTP::Get, '/message', params)
    return res
  end

  def converse(session_id, msg, context={}, reset=nil)
    if !context.is_a?(Hash)
      raise WitException.new('context should be a Hash')
    end
    params = {}
    params[:q] = msg unless msg.nil?
    params[:session_id] = session_id
    params[:reset] = true if reset
    res = req(logger, @access_token, Net::HTTP::Post, '/converse', params, context)
    return res
  end

  def __run_actions(session_id, current_request, message, context, i)
    if i <= 0
      raise WitException.new('Max steps reached, stopping.')
    end
    json = converse(session_id, message, context)
    if json['type'].nil?
      raise WitException.new('Couldn\'t find type in Wit response')
    end
    if current_request != @_sessions[session_id]
      return context
    end

    logger.debug("Context: #{context}")
    logger.debug("Response type: #{json['type']}")

    # backwards-compatibility with API version 20160516
    if json['type'] == 'merge'
      json['type'] = 'action'
      json['action'] = 'merge'
    end

    if json['type'] == 'error'
      raise WitException.new('Oops, I don\'t know what to do.')
    end

    if json['type'] == 'stop'
      return context
    end

    request = {
      'session_id' => session_id,
      'context' => context.clone,
      'text' => message,
      'entities' => json['entities']
    }
    if json['type'] == 'msg'
      throw_if_action_missing(:send)
      response = {
        'text' => json['msg'],
        'quickreplies' => json['quickreplies'],
      }
      @actions[:send].call(request, response)
    elsif json['type'] == 'action'
      action = json['action'].to_sym
      throw_if_action_missing(action)
      context = @actions[action].call(request)
      if context.nil?
        logger.warn('missing context - did you forget to return it?')
        context = {}
      end
    else
      raise WitException.new("unknown type: #{json['type']}")
    end

    if current_request != @_sessions[session_id]
      return context
    end

    return __run_actions(session_id, current_request, nil, context, i - 1)
  end

  def run_actions(session_id, message, context={}, max_steps=DEFAULT_MAX_STEPS)
    if !@actions
      throw_must_have_actions
    end
    if !context.is_a?(Hash)
      raise WitException.new('context should be a Hash')
    end

    # Figuring out whether we need to reset the last turn.
    # Each new call increments an index for the session.
    # We only care about the last call to run_actions.
    # All the previous ones are discarded (preemptive exit).
    current_request = 1
    if @_sessions.has_key?(session_id)
      current_request = @_sessions[session_id] + 1
    end
    @_sessions[session_id] = current_request

    context = __run_actions(session_id, current_request, message, context, max_steps)

    # Cleaning up once the last call to run_actions finishes.
    if current_request == @_sessions[session_id]
      @_sessions.delete(session_id)
    end

    return context
  end

  def interactive(context={}, max_steps=DEFAULT_MAX_STEPS)
    if !@actions
      throw_must_have_actions
    end

    session_id = SecureRandom.uuid
    while true
      print '> '
      msg = gets.strip
      if msg == ''
        next
      end

      begin
        context = run_actions(session_id, msg, context, max_steps)
      rescue WitException => exp
        logger.error("error: #{exp.message}")
      end
    end
  rescue Interrupt => _exp
    puts
  end

  def throw_if_action_missing(action_name)
    if !@actions.has_key?(action_name)
      raise WitException.new("unknown action: #{action_name}")
    end
  end

  def throw_must_have_actions()
    raise WitException.new('You must provide the `actions` parameter to be able to use runActions. ' + LEARN_MORE)
  end

  private :__run_actions
end
