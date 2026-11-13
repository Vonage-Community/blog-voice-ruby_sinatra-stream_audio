require 'sinatra'
require 'vonage'
require 'dotenv/load'
require 'json'

# The public URL Vonage uses to reach this server, e.g. the URL shown by
# `vonage tunnel ngrok`. Trailing slashes are removed so paths join cleanly.
BASE_URL = ENV.fetch('BASE_URL').chomp('/')

# Audio files in ./public are served as static files by Sinatra.
SILENCE_URL = "#{BASE_URL}/silence.mp3".freeze
AUDIO_URL   = "#{BASE_URL}/voice_api_audio_streaming.mp3".freeze

# `vonage tunnel ngrok` forwards to port 3000 by default.
set :port, ENV.fetch('PORT', 3000).to_i

# Sinatra 4.1+ only accepts requests for localhost in development mode.
# Allow the tunnel host so Vonage's webhooks are not rejected.
set :host_authorization, { permitted_hosts: ['localhost', URI(BASE_URL).host] }

client = Vonage::Client.new(
  application_id: ENV.fetch('VONAGE_APPLICATION_ID'),
  private_key: File.read(ENV.fetch('VONAGE_PRIVATE_KEY_PATH')),
  signature_secret: ENV.fetch('VONAGE_SIGNATURE_SECRET')
)

helpers do
  # Vonage signs Voice API webhooks with a JWT in the Authorization header.
  # Verify it before acting on the request.
  def valid_vonage_signature?(client)
    token = request.env['HTTP_AUTHORIZATION'].to_s.delete_prefix('Bearer ')
    client.voice.verify_webhook_token(token: token)
  rescue JWT::DecodeError
    false
  end
end

# Visit this route in a browser to place the call.
get '/call' do
  response = client.voice.create(
    to: [{ type: 'phone', number: ENV.fetch('VONAGE_TO_NUMBER') }],
    from: { type: 'phone', number: ENV.fetch('VONAGE_FROM_NUMBER') },
    answer_url: ["#{BASE_URL}/answer"],
    event_url: ["#{BASE_URL}/event"]
  )

  "Calling #{ENV.fetch('VONAGE_TO_NUMBER')}. Call UUID: #{response.uuid}"
rescue Vonage::Error => e
  logger.error(e.message)
  halt 500, "Could not place the call: #{e.message}"
end

# Vonage requests this route when the call is answered. The NCCO loops a
# silent file forever, which keeps the call open so we can stream into it.
get '/answer' do
  content_type :json
  [{ action: 'stream', streamUrl: [SILENCE_URL], loop: 0 }].to_json
end

# Vonage sends call status updates here. Once the call is answered, stream
# the audio file into it.
post '/event' do
  halt 401 unless valid_vonage_signature?(client)

  event = JSON.parse(request.body.read)
  logger.info("Call #{event['uuid']} is #{event['status']}")

  if event['status'] == 'answered'
    client.voice.stream.start(event['uuid'], stream_url: [AUDIO_URL])
  end

  status 204
end
