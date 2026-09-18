import http.server, os
os.chdir(os.path.join(os.path.dirname(__file__), "export"))
class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()
http.server.HTTPServer(("", 8001), Handler).serve_forever()
