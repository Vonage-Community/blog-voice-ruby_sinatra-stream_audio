ENV['RACK_ENV'] = 'test'

require 'openssl'
require 'tmpdir'

# Test configuration. Set before loading the app so no real .env is needed.
PRIVATE_KEY_FILE = File.join(Dir.mktmpdir, 'private.key')
File.write(PRIVATE_KEY_FILE, OpenSSL::PKey::RSA.new(2048).to_pem)

ENV['VONAGE_APPLICATION_ID']   = 'aaaaaaaa-bbbb-cccc-dddd-0123456789ab'
ENV['VONAGE_PRIVATE_KEY_PATH'] = PRIVATE_KEY_FILE
ENV['VONAGE_SIGNATURE_SECRET'] = 'test-signature-secret'
ENV['VONAGE_FROM_NUMBER']      = '14155550100'
ENV['VONAGE_TO_NUMBER']        = '14155550199'
ENV['BASE_URL']                = 'https://example.ngrok.app/'

require 'minitest/autorun'
require 'rack/test'
require 'webmock/minitest'
require 'jwt'
require_relative '../server'

class ServerTest < Minitest::Test
  include Rack::Test::Methods

  TUNNEL_HOST = 'example.ngrok.app'.freeze
  CALL_UUID = '63f61863-4a51-4f6b-86e1-46edebcf9356'.freeze

  def app
    Sinatra::Application
  end

  def setup
    header 'Host', TUNNEL_HOST
  end

  def signed_token(secret: ENV['VONAGE_SIGNATURE_SECRET'])
    JWT.encode({ iat: Time.now.to_i, iss: 'Vonage' }, secret, 'HS256')
  end

  def post_event(payload, token: signed_token)
    header 'Authorization', "Bearer #{token}" if token
    header 'Content-Type', 'application/json'
    post '/event', payload.to_json
  end

  def test_call_places_call_from_vonage_number_to_recipient
    stub = stub_request(:post, 'https://api.nexmo.com/v1/calls').with(
      body: {
        to: [{ type: 'phone', number: '14155550199' }],
        from: { type: 'phone', number: '14155550100' },
        answer_url: ['https://example.ngrok.app/answer'],
        event_url: ['https://example.ngrok.app/event']
      }
    ).to_return(
      status: 201,
      headers: { 'Content-Type' => 'application/json' },
      body: { uuid: CALL_UUID, status: 'started' }.to_json
    )

    get '/call'

    assert_requested stub
    assert last_response.ok?
    assert_includes last_response.body, CALL_UUID
  end

  def test_call_reports_api_errors
    stub_request(:post, 'https://api.nexmo.com/v1/calls').to_return(
      status: 401,
      headers: { 'Content-Type' => 'application/json' },
      body: { title: 'Unauthorized' }.to_json
    )

    get '/call'

    assert_equal 500, last_response.status
    assert_includes last_response.body, 'Could not place the call'
  end

  def test_answer_returns_ncco_that_loops_silence
    get '/answer'

    assert last_response.ok?
    assert_equal 'application/json', last_response.media_type
    assert_equal(
      [{ 'action' => 'stream', 'streamUrl' => ['https://example.ngrok.app/silence.mp3'], 'loop' => 0 }],
      JSON.parse(last_response.body)
    )
  end

  def test_audio_files_are_served
    get '/silence.mp3'
    assert last_response.ok?

    get '/voice_api_audio_streaming.mp3'
    assert last_response.ok?
  end

  def test_answered_event_streams_audio_into_the_call
    stub = stub_request(:put, "https://api.nexmo.com/v1/calls/#{CALL_UUID}/stream")
           .with(body: { stream_url: ['https://example.ngrok.app/voice_api_audio_streaming.mp3'] })
           .to_return(
             status: 200,
             headers: { 'Content-Type' => 'application/json' },
             body: { message: 'Stream started', uuid: CALL_UUID }.to_json
           )

    post_event({ uuid: CALL_UUID, status: 'answered' })

    assert_requested stub
    assert_equal 204, last_response.status
  end

  def test_other_events_do_not_stream_audio
    %w[started ringing completed].each do |call_status|
      post_event({ uuid: CALL_UUID, status: call_status })
      assert_equal 204, last_response.status
    end

    assert_not_requested :put, %r{api\.nexmo\.com/v1/calls/.*/stream}
  end

  def test_event_without_signature_is_rejected
    post_event({ uuid: CALL_UUID, status: 'answered' }, token: nil)

    assert_equal 401, last_response.status
    assert_not_requested :put, %r{api\.nexmo\.com}
  end

  def test_event_with_wrong_signature_is_rejected
    post_event({ uuid: CALL_UUID, status: 'answered' }, token: signed_token(secret: 'wrong-secret'))

    assert_equal 401, last_response.status
    assert_not_requested :put, %r{api\.nexmo\.com}
  end

  def test_event_with_malformed_token_is_rejected
    post_event({ uuid: CALL_UUID, status: 'answered' }, token: 'not-a-jwt')

    assert_equal 401, last_response.status
  end

  def test_requests_for_unknown_hosts_are_blocked
    header 'Host', 'attacker.example.com'
    get '/answer'

    assert_equal 403, last_response.status
  end

  def test_localhost_is_allowed
    header 'Host', 'localhost'
    get '/answer'

    assert last_response.ok?
  end
end
