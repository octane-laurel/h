#!/usr/bin/env python3
# Multi-file Gemini runner: files -> combined prompt -> out.sh

PROMPT = """
"""
# Prefer env var; you can also pass --key
api_key = ""  # optional inline default

import argparse, os, sys, re
from pathlib import Path

# pip install google-genai
from google import genai

MODEL = "gemini-2.5-flash"  # see model list in docs
# in cmd
#   set GEMINI_API_KEY=your_key_her


import sys

def force_utf8_stdio():
    """
    Try to make stdout/stderr UTF-8. If not possible (older Python),
    leave them as-is; we'll still fall back to binary writes.
    """
    try:
        if hasattr(sys.stdout, "reconfigure"):
            sys.stdout.reconfigure(encoding="utf-8", errors="strict")
        if hasattr(sys.stderr, "reconfigure"):
            sys.stderr.reconfigure(encoding="utf-8", errors="strict")
    except Exception:
        pass

def safe_print(s: str):
    """
    Print text; if the active code page can't encode it,
    write UTF-8 bytes directly to stdout.
    """
    try:
        print(s)
    except UnicodeEncodeError:
        try:
            sys.stdout.buffer.write(s.encode("utf-8"))
            sys.stdout.buffer.write(b"\n")
        except Exception:
            # last resort: replace unencodable chars
            print(s.encode(sys.stdout.encoding or "utf-8", errors="replace").decode(sys.stdout.encoding or "utf-8"))


def get_client(cli_key: str | None) -> genai.Client:
    key = (cli_key or os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY") or api_key).strip()
    if not key:
        print("No valid API key. Use --key, set GEMINI_API_KEY/GOOGLE_API_KEY, or edit api_key.", file=sys.stderr)
        sys.exit(1)
    return genai.Client(api_key=key)

def read_text(p: Path) -> str:
    try:
        return p.read_text(encoding="utf-8")
    except Exception as e:
        print(f"Failed to read {p}: {e}", file=sys.stderr)
        sys.exit(2)

def write_unix(p: Path, content: str) -> None:
    try:
        if not content.startswith("#!"):
            content = "#!/bin/bash\n" + content
        p.write_text(content, encoding="utf-8", newline="\n")
        try:
            os.chmod(p, 0o755)
        except Exception:
            pass
    except Exception as e:
        print(f"Failed to write {p}: {e}", file=sys.stderr)
        sys.exit(3)

def extract_shell_from_response(text: str, force_raw: bool = False) -> str:
    if force_raw:
        return text
    fence_pattern = re.compile(r"```(?:\s*(?:bash|sh|zsh))?\n(.*?)```", re.DOTALL | re.IGNORECASE)
    m = fence_pattern.search(text)
    if m:
        return m.group(1).strip()
    generic_pattern = re.compile(r"```\n(.*?)```", re.DOTALL)
    m2 = generic_pattern.search(text)
    if m2:
        return m2.group(1).strip()
    return text.strip()

def run_once(client: genai.Client, prompt: str) -> str:
    # Pass a single string; SDK handles it
    resp = client.models.generate_content(
        model=MODEL,
        contents=prompt,
        # Optional config:
        # config={"temperature": 0.2, "max_output_tokens": 8192}
    )
    return resp.text or ""

def chat_console(client: genai.Client) -> None:
    """
    Interactive console without using types.Part/Content.
    Maintains a simple transcript string to avoid SDK typing quirks.
    """
    transcript = ""
    while True:
        try:
            msg = input("> ").strip()
        except (EOFError, KeyboardInterrupt):
            return
        if msg.lower() == "exit":
            return

        # Append user message and a marker for the assistant
        if transcript:
            transcript += "\n"
        transcript += f"User: {msg}\nAssistant:"

        # Generate using the whole transcript as context
        resp = client.models.generate_content(model=MODEL, contents=transcript)
        reply = (resp.text or "").strip()
        print(reply)

        # Append the assistant's reply to the transcript
        transcript += f" {reply}"

def parse_args():
    ap = argparse.ArgumentParser(
        description=(
            "Combine one or more input files into a single prompt (order matters), "
            "send to Gemini 2.5 Flash, and write to an executable .sh file. "
            "If no input files are provided, opens an interactive chat console."
        )
    )
    ap.add_argument("inputs", nargs="*", type=Path, help="One or more input files (order defines concatenation)")
    ap.add_argument("-o", "--output", type=Path, help="Path to output shell script (e.g., out.sh)")
    ap.add_argument("--key", help="Gemini API key (overrides env and inline)")
    ap.add_argument("--raw", action="store_true", help="Write model output as-is (do not strip ``` fences)")
    ap.add_argument("-s", "--show", action="store_true", help="Show combined prompt to stdout and exit")
    return ap.parse_args()

def build_prompt_from_files(files: list[Path]) -> str:
    parts: list[str] = []
    header = PROMPT.strip()
    if header:
        parts.append(header)
    for p in files:
        text = read_text(p).strip()
        parts.append(text)
    return "\n".join(parts).strip() + "\n"

def main():
    force_utf8_stdio()
    args = parse_args()
    client = get_client(args.key)

    if not args.inputs:
        chat_console(client)
        return

    prompt = build_prompt_from_files(args.inputs)

    if args.show:
        safe_print(prompt)   # <— use the safe print
        return

    if not args.output:
        print("Error: -o/--output is required when providing input files unless using -s/--show.", file=sys.stderr)
        sys.exit(4)

    result = run_once(client, prompt)
    cleaned = extract_shell_from_response(result, force_raw=args.raw)

    write_unix(args.output, cleaned)
    print(f"Wrote {len(cleaned)} bytes (LF newlines, executable) -> {args.output}")

if __name__ == "__main__":
    main()
