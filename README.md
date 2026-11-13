# Stream Audio into a Phone Call with Ruby

This demo uses Ruby, [Sinatra](https://sinatrarb.com/) and the [Vonage Voice API](https://developer.vonage.com/en/voice/voice-api/overview) to call a phone number and stream an audio file into the call once it is answered.

## How it works

1. Visiting `/call` asks the Voice API to call `VONAGE_TO_NUMBER` from your Vonage number.
2. When the call is answered, Vonage fetches `/answer`. That route returns an NCCO that loops a silent audio file, which keeps the call open.
3. Vonage sends call status updates to `/event`. When the status is `answered`, the app verifies the webhook signature and uses the [Stream Audio](https://developer.vonage.com/en/voice/voice-api/code-snippets/controlling-media/play-an-audio-stream-into-a-call) endpoint to play `public/voice_api_audio_streaming.mp3` into the call.

## Prerequisites

- Ruby 3.3 or newer
- A [Vonage API account](https://developer.vonage.com/sign-up)
- The [Vonage CLI](https://developer.vonage.com/en/vonage-cli/getting-started) (requires Node.js)
- An [ngrok](https://ngrok.com/) account and its auth token

## Set up

### 1. Install dependencies

```bash
git clone https://github.com/Vonage-Community/blog-voice-ruby_sinatra-stream_audio.git
```

```bash
cd blog-voice-ruby_sinatra-stream_audio
```

```bash
bundle install
```

### 2. Configure the Vonage CLI

Install the CLI and log in with the API key and secret from the [Vonage Dashboard](https://dashboard.vonage.com):

```bash
npm install -g @vonage/cli
```

```bash
vonage auth set --api-key=YOUR_API_KEY --api-secret=YOUR_API_SECRET
```

### 3. Buy a number

Search for a voice-enabled number, then buy one (replace `US` with your country code):

```bash
vonage numbers search US --features=VOICE
```

```bash
vonage numbers buy US NUMBER
```

### 4. Create a Vonage application

Run this from the project folder. It creates the application and saves its private key as `private.key`:

```bash
vonage apps create "Stream Audio Demo"
```

Add the Voice capability, using the application ID from the previous output. The URLs are placeholders: `vonage tunnel ngrok` points them at your tunnel later. `--voice-signed-callbacks` makes Vonage sign every webhook so the app can verify it.

```bash
vonage apps capabilities update APP_ID voice --voice-answer-url=https://example.com/answer --voice-event-url=https://example.com/event --voice-fallback-url=https://example.com/fallback --voice-signed-callbacks
```

### 5. Open a tunnel

Vonage needs a public URL to reach your local server. In a second terminal, set your ngrok auth token and open a tunnel to port 3000:

```bash
export NGROK_AUTHTOKEN=YOUR_NGROK_AUTHTOKEN
```

```bash
vonage tunnel ngrok APP_ID
```

Leave it running and copy the URL shown next to `Forwarding`. Press `q` to close the tunnel when you're done.

### 6. Set your environment variables

```bash
cp .env.example .env
```

Fill in `.env`:

| Variable | Value |
| --- | --- |
| `VONAGE_APPLICATION_ID` | The ID from `vonage apps create` |
| `VONAGE_PRIVATE_KEY_PATH` | `./private.key` |
| `VONAGE_SIGNATURE_SECRET` | Your signature secret from [API Settings](https://dashboard.vonage.com/settings) in the Dashboard |
| `VONAGE_FROM_NUMBER` | The number you bought |
| `VONAGE_TO_NUMBER` | The phone number to call |
| `BASE_URL` | The tunnel URL from step 5 |

Numbers use E.164 format without a leading `+`, for example `14155550100`.

ngrok gives you a new URL each time you open a tunnel unless you use a static domain, so update `BASE_URL` whenever it changes.

## Run the app

```bash
bundle exec ruby server.rb
```

Open [http://localhost:3000/call](http://localhost:3000/call) in your browser. Your phone rings, and the audio plays when you answer.

## Run the tests

The tests stub the Vonage API, so they don't need an account or make real calls:

```bash
bundle exec rake test
```

## Get help

Join the [Vonage Community Slack](https://developer.vonage.com/en/community/slack).

## License

This project is released under the [MIT License](LICENSE).
