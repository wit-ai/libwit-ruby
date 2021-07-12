# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

require 'json'
require 'logger'
require 'net/http'
require 'securerandom'

class Wit
  class Error < StandardError; end

  WIT_API_HOST = ENV['WIT_URL'] || 'https://api.wit.ai'
  WIT_API_VERSION = ENV['WIT_API_VERSION']  || '20200513'
  LEARN_MORE = 'Learn more at https://wit.ai/docs/quickstart'

  def initialize(opts = {})
    @access_token = opts[:access_token]

    if opts[:logger]
      @logger = opts[:logger]
    end
  end

  def logger
    @logger ||= begin
      x = Logger.new(STDOUT)
      x.level = Logger::INFO
      x
    end
  end

  def message(msg, n=nil, verbose=nil)
    params = {}
    params[:q] = msg unless msg.nil?
    params[:n] = n unless n.nil?
    params[:verbose] = verbose unless verbose.nil?
    res = req(logger, @access_token, Net::HTTP::Get, '/message', params)
    return res
  end

  def interactive(handle_message=nil, context={})
    while true
      print '> '
      msg = STDIN.gets.strip
      if msg == ''
        next
      end

      begin
        if handle_message.nil?
          puts(message(msg))
        else
          puts(handle_message.call(message(msg)))
        end
      rescue Error => exp
        logger.error("error: #{exp.message}")
      end
    end
  rescue Interrupt => _exp
    puts
  end

  def create_new_app(payload, set_new_app_token = false)
    response = req(logger, @access_token, Net::HTTP::Post, "/apps", {}, payload)
    @access_token = response['access_token'] if set_new_app_token
    return response
  end

  def post_utterances(payload)
    payload = [payload] if payload.is_a? Hash

    payload.each do |utterance|
      unless utterance[:entities].empty?
        utterance[:entities] = validate_entities utterance[:entities]
      end
      validate_payload utterance
    end
    req(logger, @access_token, Net::HTTP::Post, "/utterances", {}, payload)
  end

  def get_intents
    req(logger, @access_token, Net::HTTP::Get, "/intents")
  end

  def get_intent(intent)
    req(logger, @access_token, Net::HTTP::Get, "/intents/#{URI.encode(intent)}")
  end

  def post_intents(payload)
    req(logger, @access_token, Net::HTTP::Post, "/intents", {}, payload)
  end

  def delete_intents(intent)
    req(logger, @access_token, Net::HTTP::Delete, "/intents/#{URI.encode(intent)}")
  end

  def get_entities
    req(logger, @access_token, Net::HTTP::Get, "/entities")
  end

  def post_entities(payload)
    payload = payload.map {|k, v| [(k.to_sym rescue k), v]}.to_h.reject{ |k| ![:name, :roles, :lookups, :keywords].include?(k) }
    validate_payload payload
    req(logger, @access_token, Net::HTTP::Post, "/entities", {}, payload)
  end

  def get_entity(entity)
    req(logger, @access_token, Net::HTTP::Get, "/entities/#{URI.encode(entity)}")
  end

  def put_entities(entity, payload)
    payload = payload.map {|k, v| [(k.to_sym rescue k), v]}.to_h.reject{ |k| ![:name, :roles, :lookups, :keywords].include?(k) }
    validate_payload payload
    req(logger, @access_token, Net::HTTP::Put, "/entities/#{URI.encode(entity)}", {}, payload)
  end

  def delete_entities(entity)
    req(logger, @access_token, Net::HTTP::Delete, "/entities/#{URI.encode(entity)}")
  end

  def post_entities_keywords(entity, payload)
    payload = payload.map {|k, v| [(k.to_sym rescue k), v]}.to_h.reject{ |k| ![:keyword, :synonyms].include?(k) }
    validate_payload payload
    req(logger, @access_token, Net::HTTP::Post, "/entities/#{URI.encode(entity)}/keywords", {}, payload)
  end

  def delete_entities_keywords(entity, keyword)
    req(logger, @access_token, Net::HTTP::Delete, "/entities/#{URI.encode(entity)}/keywords/#{URI.encode(keyword)}")
  end

  def post_entities_keywords_synonyms(entity, keyword, payload)
    payload = payload.map {|k, v| [(k.to_sym rescue k), v]}.to_h.reject{ |k| ![:synonym].include?(k) }
    validate_payload payload
    req(logger,@access_token, Net::HTTP::Post, "/entities/#{URI.encode(entity)}/keywords/#{URI.encode(keyword)}/synonyms", {}, payload)
  end

  def delete_entities_keywords_synonyms(entity, keyword, synonym)
    req(logger,@access_token, Net::HTTP::Delete, "/entities/#{URI.encode(entity)}/keywords/#{URI.encode(keyword)}/synonyms/#{URI.encode(synonym)}")
  end

  def get_traits
    req(logger, @access_token, Net::HTTP::Get, "/traits")
  end

  def get_trait(trait)
    req(logger, @access_token, Net::HTTP::Get, "/traits/#{URI.encode(trait)}")
  end

  def post_traits(payload)
    req(logger, @access_token, Net::HTTP::Post, "/traits", {}, payload)
  end

  def post_traits_values(trait, payload)
    req(logger, @access_token, Net::HTTP::Post, "/traits/#{URI.encode(trait)}/values", {}, payload)
  end

  def delete_traits_values(trait, value)
    req(logger, @access_token, Net::HTTP::Delete, "/traits/#{URI.encode(trait)}/values/#{URI.encode(value)}")
  end

  def delete_traits(trait)
    req(logger, @access_token, Net::HTTP::Delete, "/traits/#{URI.encode(trait)}")
  end

  private

  def validate_payload(payload)
    key_types = {
      id: String,
      name: String,
      roles: Array,
      lookups: Array,
      keywords: Array,
      keyword: String,
      synonyms: Array,
      text: String,
      intent: String,
      entities: Array,
      traits: Array
    }
    payload.each do |k, v|
      raise Error.new("#{k.to_s} in request body must be #{key_types[k].to_s} type") unless key_types[k] == v.class
    end
  end

  def validate_entities(entities)
    entity_keys = {
      entity: String,
      start: Integer,
      end: Integer,
      body: String,
      entities: Array
    }
    entities.each do |entity|
      entity = entity.map {|k, v| [(k.to_sym rescue k), v]}.to_h.reject{ |k| !entity_keys.keys.include?(k) }
      entity.each do |k, v|
        if k == :entities && !v.empty?
          validate_entities(v)
        end
        raise Error.new("#{k.to_s} in entities body must be #{entity_keys[k].to_s} type") unless entity_keys[k] == v.class
      end
    end

    return entities
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
      json = JSON.parse(rsp.body)
      if rsp.code.to_i != 200
        error_msg = (json.is_a?(Hash) and json.has_key?('error')) ?  json['error'] : json
        raise Error.new("Wit responded with an error: #{error_msg}")
      end
      logger.debug("#{meth_class} #{uri} #{json}")
      json
    end
  end
end
