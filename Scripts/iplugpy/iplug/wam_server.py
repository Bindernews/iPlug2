import argparse
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler

class CustomHandler(SimpleHTTPRequestHandler):
  def __init__(self, *args, **kwargs):
    super().__init__(*args, **kwargs)
    self.extensions_map['.wasm'] = 'application/wasm'

def main(argv = None):
  if argv is None:
    argv = sys.argv[1:]
  
  parser = argparse.ArgumentParser(prog="wam_server")
  parser.add_argument("--port", type=int, default=8000, help="Listening port")
  args = parser.parse_args(argv)

  httpd = HTTPServer(("localhost", args.port), CustomHandler)
  print(f"Serving at http://localhost:{args.port}/ waiting for connections")
  httpd.serve_forever()

if __name__ == "__main__":
  main()
