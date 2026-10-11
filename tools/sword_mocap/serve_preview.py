"""Serve only a named exported lab directory on loopback; preserve other previews."""
import argparse,functools
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
class Preview(SimpleHTTPRequestHandler):
 def end_headers(self):
  self.send_header('Cache-Control','no-store');self.send_header('Cross-Origin-Opener-Policy','same-origin');self.send_header('Cross-Origin-Embedder-Policy','require-corp');super().end_headers()
def main():
 a=argparse.ArgumentParser();a.add_argument('--directory',type=Path,required=True);a.add_argument('--port',type=int,default=8791);args=a.parse_args();directory=args.directory.resolve(strict=True)
 if not (directory/'index.html').is_file():raise SystemExit('Expected exported lab index.html')
 s=ThreadingHTTPServer(('127.0.0.1',args.port),functools.partial(Preview,directory=str(directory)))
 print(f'Preview http://127.0.0.1:{args.port}/ from {directory}',flush=True);s.serve_forever()
if __name__=='__main__':main()
