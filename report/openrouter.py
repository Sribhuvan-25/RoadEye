"""Minimal OpenRouter chat client.

OpenRouter exposes an OpenAI-compatible /chat/completions endpoint, so one
client reaches any model behind a single model-id string. Key comes from the
OPENROUTER_API_KEY environment variable, or a gitignored .env file (repo root
or report/); model is passed in (config-driven, not hardcoded) so models can
be A/B'd without code changes. Uses only the standard library so the report
module has no new dependencies.
"""
import json
import os
import urllib.error
import urllib.request
from pathlib import Path

API_URL = "https://openrouter.ai/api/v1/chat/completions"
DEFAULT_MODEL = "anthropic/claude-sonnet-4.5"

_ENV_PATHS = [
    Path(__file__).resolve().parent.parent / ".env",
    Path(__file__).resolve().parent / ".env",
]


class OpenRouterError(RuntimeError):
    pass


def _key_from_env_file() -> str:
    """Read OPENROUTER_API_KEY from a .env file without any dependency.

    Parses only KEY=value lines; ignores blanks and # comments; strips optional
    surrounding quotes. Never logs the value.
    """
    for path in _ENV_PATHS:
        if not path.is_file():
            continue
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, _, value = line.partition("=")
            if name.strip() == "OPENROUTER_API_KEY":
                return value.strip().strip('"').strip("'")
    return ""


def get_api_key() -> str:
    key = os.environ.get("OPENROUTER_API_KEY") or _key_from_env_file()
    if not key:
        raise OpenRouterError(
            "OPENROUTER_API_KEY not found. Set it one of two ways:\n"
            "  export OPENROUTER_API_KEY=sk-or-...\n"
            "  or put OPENROUTER_API_KEY=sk-or-... in a .env file "
            "(repo root or report/); both are gitignored."
        )
    return key


def complete(
    system_prompt: str,
    user_content: str,
    model: str = DEFAULT_MODEL,
    temperature: float = 0.0,
    max_tokens: int = 2000,
    timeout_s: float = 120.0,
) -> str:
    """One chat completion. temperature 0 for run-to-run consistency.

    max_tokens caps the reply. A dedup'd session is ~20-50 defects, so a full
    report fits well under 2000 tokens; without a cap OpenRouter reserves the
    model's entire context and bills affordability against that worst case.
    """
    body = json.dumps({
        "model": model,
        "temperature": temperature,
        "max_tokens": max_tokens,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_content},
        ],
    }).encode("utf-8")

    req = urllib.request.Request(
        API_URL,
        data=body,
        headers={
            "Authorization": f"Bearer {get_api_key()}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://github.com/Sribhuvan-25/Road-Analysis",
            "X-Title": "RoadEye Inspection Report",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        raise OpenRouterError(f"OpenRouter HTTP {e.code}: {detail}") from e
    except urllib.error.URLError as e:
        raise OpenRouterError(f"OpenRouter request failed: {e.reason}") from e

    try:
        return data["choices"][0]["message"]["content"]
    except (KeyError, IndexError) as e:
        raise OpenRouterError(f"Unexpected OpenRouter response: {data}") from e
