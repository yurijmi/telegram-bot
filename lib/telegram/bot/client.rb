require 'curb'
require 'json'

module Telegram
  module Bot
    class Client
      URL_TEMPLATE = 'https://api.telegram.org/bot%<token>s/'.freeze
      
      autoload :TypedResponse, 'telegram/bot/client/typed_response'
      extend Initializers
      prepend Async
      include DebugClient
      
      require 'telegram/bot/client/api_helper'
      include ApiHelper
      
      class << self
        def by_id(id)
          Telegram.bots[id]
        end
        
        # Prepend TypedResponse module.
        def typed_response!
          prepend TypedResponse
        end
        
        def prepare_async_args(action, body = {})
          [action.to_s, Async.prepare_hash(prepare_body(body))]
        end
        
        def error_for_response(client)
          result = JSON.parse(client.body_str) rescue nil # rubocop:disable RescueModifier
          
          unless result
            return Error.new("#{client.status}: no valid JSON received")
          end
          
          message = result['description'] || '-'
          
          # This errors are raised only for valid responses from Telegram
          case client.status.to_i
          when 403
            Forbidden.new(message)
          when 404
            NotFound.new(message)
          else
            Error.new("#{client.status}: #{message}")
          end
        end
      end
      
      attr_reader :client, :token, :username, :base_uri
      
      def initialize(token = nil, username = nil, **options)
        @token    = token    || options[:token]
        @username = username || options[:username]
        @base_uri = format(URL_TEMPLATE, token: self.token)
        
        @client = Curl::Easy.new(@base_uri) do |curl|
          curl.set :TCP_KEEPALIVE, 1
          curl.set :TCP_KEEPIDLE,  120
          curl.set :TCP_KEEPINTVL, 30
          
          curl.version = Curl::HTTP_2_0
          curl.connect_timeout = 5
          curl.encoding = 'gzip'
          
          curl.headers['User-Agent'] = 'Ruby/TelegramBot'
          
          curl.verbose = true
        end
      end
      
      def request(action, params = {})
        http_request("#{base_uri}#{action}", params)
        
        if client.status.to_i >= 300
          raise self.class.error_for_response(client)
        end
        
        JSON.parse(client.body_str)
      end
      
      # Endpoint for low-level request. For easy host highjacking & instrumentation.
      # Params are not used directly but kept for instrumentation purpose.
      # You probably don't want to use this method directly.
      def http_request(url, params)
        params = params.map do |k, v|
          case v
          when Hash, Array
            Curl::PostField.content(k.to_s, v.to_json)
          when File
            client.multipart_form_post = true
            
            Curl::PostField.file(k.to_s, v.path)
          else
            Curl::PostField.content(k.to_s, v.to_s)
          end
        end
        
        client.url = url
        client.http_post(*params)
        
        client.multipart_form_post = false
      end
      
      def inspect
        "#<#{self.class.name}##{object_id}(#{@username})>"
      end
    end
  end
end
