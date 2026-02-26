from __future__ import annotations

import os
from pathlib import Path
from typing import Optional

from openai import OpenAI


ROOT_DIR = Path(__file__).resolve().parent
ENV_PATH = ROOT_DIR / ".env"


def _load_env(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        entry = line.strip()
        if not entry or entry.startswith("#") or "=" not in entry:
            continue
        key, value = entry.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def _ensure_api_key() -> str:
    env_key = os.getenv("OPENAI_API_KEY")
    if env_key:
        return env_key.strip()
    file_values = _load_env(ENV_PATH)
    key = file_values.get("OPENAI_API_KEY", "").strip()
    if not key:
        raise RuntimeError("Missing OPENAI_API_KEY in .env or environment.")
    os.environ["OPENAI_API_KEY"] = key
    return key


def _extract_output_text(response: object) -> Optional[str]:
    output_text = getattr(response, "output_text", None)
    if isinstance(output_text, str) and output_text.strip():
        return output_text.strip()
    
    # If output_text is not directly available, check 'output'
    output = getattr(response, "output", None)
    if isinstance(output, list):
        texts: list[str] = []
        for item in output:
            content = getattr(item, "content", None) if item is not None else None
            if not content:
                continue
            for part in content:
                part_type = getattr(part, "type", None)
                if part_type in {"output_text", "text"}:
                    text = getattr(part, "text", "")
                    if text:
                        texts.append(text)
        joined = "\n".join(texts).strip()
        return joined or None
    return None


def summarize_transcript(text: str, video_id: str = "") -> str:
    if not text.strip():
        raise ValueError("Missing transcript text.")

    _ensure_api_key()
    client = OpenAI()

    prompt = (
        "Summarize the following YouTube transcript in a professional tone. "
        "Provide a short paragraph followed by 5-8 concise bullet points.\n\n"
        f"{text}"
    )
    response = client.responses.create(
        model="gpt-5-nano",
        input=prompt,
        max_output_tokens=1024,
    )
    summary = _extract_output_text(response) or ""
    if not summary.strip():
        raise RuntimeError("Empty summary returned.")
    return summary.strip()
