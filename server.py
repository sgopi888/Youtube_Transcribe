from __future__ import annotations

import json
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from youtube_transcript_api import YouTubeTranscriptApi
from openai_client import summarize_transcript


ROOT_DIR = Path(__file__).resolve().parent
STATIC_DIR = ROOT_DIR / "ui"


class TranscriptHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(STATIC_DIR), **kwargs)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/transcript":
            self._handle_transcript(parsed)
            return
        super().do_GET()

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/summarize":
            self._handle_summarize()
            return
        self.send_error(404, "Not Found")

    def _handle_transcript(self, parsed) -> None:
        params = parse_qs(parsed.query)
        video_id = (params.get("video_id") or [""])[0].strip()

        if not video_id:
            self._send_json({"error": "Missing video_id"}, status=400)
            return

        try:
            ytt_api = YouTubeTranscriptApi()
            result = ytt_api.fetch(video_id)
            transcript = " ".join(snippet.text for snippet in result.snippets)
            self._send_json({"video_id": video_id, "transcript": transcript})
        except Exception as exc:
            self._send_json({"error": str(exc)}, status=500)

    def _handle_summarize(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length > 0 else b""
        try:
            payload = json.loads(raw.decode("utf-8")) if raw else {}
        except json.JSONDecodeError:
            self._send_json({"error": "Invalid JSON payload."}, status=400)
            return

        text = str(payload.get("text") or "").strip()
        video_id = str(payload.get("video_id") or "").strip()
        if not text:
            self._send_json({"error": "Missing transcript text."}, status=400)
            return

        try:
            summary = summarize_transcript(text, video_id)
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=400)
            return
        except Exception as exc:
            self._send_json({"error": f"OpenAI API error: {exc}"}, status=502)
            return

        self._send_json({"video_id": video_id, "summary": summary})

    def _send_json(self, payload: dict, status: int = 200) -> None:
        data = json.dumps(payload, ensure_ascii=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def run() -> None:
    server_address = ("127.0.0.1", 8000)
    httpd = ThreadingHTTPServer(server_address, TranscriptHandler)
    print(f"Serving on http://{server_address[0]}:{server_address[1]}")
    httpd.serve_forever()


if __name__ == "__main__":
    run()
