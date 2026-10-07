"""Serve only the standalone courtyard Web export on loopback."""
from pathlib import Path
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import argparse

class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control','no-store')
        super().end_headers()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',type=int,default=8772)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]/'.local/build/courtyard-web'
    if not (root/'index.html').is_file():raise SystemExit('Run tools/build_courtyard.py first.')
    print(f'Courtyard: http://127.0.0.1:{args.port}/',flush=True)
    server=ThreadingHTTPServer(('127.0.0.1',args.port),partial(Handler,directory=str(root)))
    try:server.serve_forever()
    except KeyboardInterrupt:pass
    finally:server.server_close()

if __name__=='__main__':main()
