# Youtube_Transcribe

Small Python project that:

1) Fetches a YouTube video transcript, and  
2) (Optionally) summarizes it via OpenAI, exposed through a tiny local web app/API.

## Project Layout

- `youtube_transcribe.py` — minimal script: fetch transcript for a `video_id` and print it.
- `server.py` — local web app + API endpoints (serves files from `ui/`).
- `openai_client.py` — OpenAI summarization helper + `.env` loading.
- `test.py` — quick smoke test for `summarize_transcript`.
- `.env` — optional local env file (do not commit secrets).

## Setup

```bash
python -m venv venv
source venv/bin/activate
pip install youtube-transcript-api openai
```

If you want to use summarization, set your API key (recommended) or put it in `.env`:

```bash
export OPENAI_API_KEY="..."
```

## 1) Run the Minimal Script (prints transcript)

Edit the `video_id` in `youtube_transcribe.py`, then run:

```bash
python youtube_transcribe.py
```

You should see the transcript text printed to stdout.

## 2) Graduate to the App Flow (local UI + API)

Start the server:

```bash
python server.py
```

Open the UI:

- `http://127.0.0.1:8000`

### API: Fetch transcript

```bash
curl -s "http://127.0.0.1:8000/api/transcript?video_id=zyNWbPBkq6E"
```

Response (example):

```json
{ "video_id": "zyNWbPBkq6E", "transcript": "..." }
```

### API: Summarize transcript (requires `OPENAI_API_KEY`)

```bash
curl -s -X POST "http://127.0.0.1:8000/api/summarize" \
  -H "Content-Type: application/json" \
  -d '{"video_id":"zyNWbPBkq6E","text":"<paste transcript here>"}'
```

Response (example):

```json
{ "video_id": "zyNWbPBkq6E", "summary": "..." }
```

### Notes / Common issues

- Some videos don’t have transcripts available (or are region/language restricted).
- If you only need transcripts, you can use `/api/transcript` without setting `OPENAI_API_KEY`.
- Keep `.env` local and never commit real API keys.

