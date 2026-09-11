import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def _send(self, body, status=200):
        raw = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        self._send({"data": [{"id": "gemma-test"}]})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        request = json.loads(self.rfile.read(length))
        completion = max(1, request["max_tokens"] // 2)
        self._send({
            "model": request["model"],
            "choices": [{"finish_reason": "length", "message": {"content": "mock"}}],
            "usage": {"prompt_tokens": 10, "completion_tokens": completion, "total_tokens": completion + 10},
        })


ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
