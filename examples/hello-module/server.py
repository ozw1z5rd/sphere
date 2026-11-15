#!/usr/bin/env python3
"""Minimal MCP stdio server used as a Sphere module example.

It speaks newline-delimited JSON-RPC 2.0 on stdout/stdin and implements just
enough of the Model Context Protocol to expose one tool.
"""

import json
import sys

PROTOCOL_VERSION = "2025-06-18"

TOOLS = [
    {
        "name": "ping",
        "description": "Return 'pong' plus an optional message.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "message": {
                    "type": "string",
                    "description": "Text to echo back.",
                }
            },
        },
    }
]


def send(payload):
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def handle(request):
    method = request.get("method")
    request_id = request.get("id")

    if request_id is None:
        # Notification: nothing to answer.
        return

    if method == "initialize":
        send(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "result": {
                    "protocolVersion": PROTOCOL_VERSION,
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "Hello Module", "version": "1.0.0"},
                    "instructions": "A tiny example module. Use the ping tool.",
                },
            }
        )
        return

    if method == "ping":
        send({"jsonrpc": "2.0", "id": request_id, "result": {}})
        return

    if method == "tools/list":
        send({"jsonrpc": "2.0", "id": request_id, "result": {"tools": TOOLS}})
        return

    if method == "tools/call":
        params = request.get("params") or {}
        if params.get("name") != "ping":
            send(
                {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "error": {"code": -32602, "message": "unknown tool"},
                }
            )
            return
        arguments = params.get("arguments") or {}
        message = arguments.get("message", "")
        text = "pong" + (f": {message}" if message else "")
        send(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "result": {"content": [{"type": "text", "text": text}], "isError": False},
            }
        )
        return

    if method in ("resources/list", "prompts/list"):
        key = "resources" if method == "resources/list" else "prompts"
        send({"jsonrpc": "2.0", "id": request_id, "result": {key: []}})
        return

    send(
        {
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {"code": -32601, "message": f"method not found: {method}"},
        }
    )


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError as error:
            sys.stderr.write(f"invalid json: {error}\n")
            continue
        handle(request)


if __name__ == "__main__":
    main()
