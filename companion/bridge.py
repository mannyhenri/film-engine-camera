#!/usr/bin/env python3
"""Authenticated LAN companion. Uses Film Engine's existing API; never its database.
Run: python3 companion/bridge.py --config .local/bridge.json
The config contains engine_url, token, host (default 0.0.0.0), port (default 5392).
"""
import argparse, base64, hashlib, hmac, json, os, re, shutil, subprocess, tempfile, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError

PROJECT = r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
CLIP = r'FEC-[0-9a-fA-F-]{36}\.mov'
UPLOAD = re.compile(r'^/projects/(' + PROJECT + r')/clips/(' + CLIP + r')$')

class BridgeServer(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address, config):
        self.config = config
        self.upload_lock = threading.Lock()
        super().__init__(address, Handler)
    def engine(self, path, body=None):
        data = None if body is None else json.dumps(body).encode()
        request = Request(self.config['engine_url'].rstrip('/') + path, data=data, headers={'Content-Type':'application/json'})
        with urlopen(request, timeout=30) as response:
            return json.load(response)

class Handler(BaseHTTPRequestHandler):
    def reply(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def authorized(self):
        expected = 'Bearer ' + self.server.config['token']
        if not hmac.compare_digest(self.headers.get('Authorization',''), expected):
            self.reply(401, {'error':'Pairing key is missing or incorrect.'})
            return False
        return True
    def do_GET(self):
        if not self.authorized(): return
        if self.path != '/projects': return self.reply(404, {'error':'Unknown route'})
        try:
            result = self.server.engine('/film/projects?limit=500')
            self.reply(200, {'projects':[{'id':p['id'],'title':p['title']} for p in result['projects']]})
        except Exception:
            self.reply(502, {'error':'Film Engine is unavailable on the Mac. Open Film Engine and retry.'})
    def do_PUT(self):
        if not self.authorized(): return
        match = UPLOAD.fullmatch(self.path)
        if not match: return self.reply(400, {'error':'Invalid project or camera filename'})
        if not self.server.upload_lock.acquire(blocking=False): return self.reply(409, {'error':'Another clip is being received. Retry shortly.'})
        partial = None
        try:
            project, name = match.groups()
            size = int(self.headers.get('Content-Length','0'))
            if size <= 0 or size > 64 * 1024**3: raise ValueError('A clip must be between 1 byte and 64 GB.')
            encoded = self.headers.get('X-Camera-Metadata','')
            if len(encoded) > 32768: raise ValueError('Slate metadata is too large.')
            metadata = json.loads(base64.b64decode(encoded, validate=True)) if encoded else {}
            if not isinstance(metadata,dict): raise ValueError('Slate metadata must be an object.')
            report = self.server.engine('/film/projects/' + project + '/storage')
            folder = next(Path(f['path']) for f in report['folders'] if f['subdir']=='video')
            folder.mkdir(parents=True, exist_ok=True)
            if shutil.disk_usage(folder).free < size + 256 * 1024**2: raise ValueError('Not enough free space on the Mac for this clip.')
            destination = folder / name
            fd, partial = tempfile.mkstemp(prefix='.camera-', suffix='.part', dir=folder)
            digest = hashlib.sha256()
            self.connection.settimeout(120)
            with os.fdopen(fd,'wb') as output:
                remaining = size
                while remaining:
                    block = self.rfile.read(min(1024**2,remaining))
                    if not block: raise ValueError('Transfer interrupted; retry the clip from your phone.')
                    output.write(block); digest.update(block); remaining -= len(block)
                output.flush(); os.fsync(output.fileno())
            with open(partial,'rb') as f:
                header=f.read(12)
            if len(header)<12 or header[4:8] not in (b'ftyp',b'wide',b'mdat',b'moov'):
                raise ValueError('The received file is not a QuickTime movie.')
            measured = {}
            probe = shutil.which('ffprobe') or ('/usr/local/bin/ffprobe' if Path('/usr/local/bin/ffprobe').exists() else None)
            if probe:
                result = subprocess.run([probe,'-v','error','-show_streams','-show_format','-of','json',partial],capture_output=True,timeout=60)
                if result.returncode: raise ValueError('The received movie could not be read.')
                measured=json.loads(result.stdout)
            sha = digest.hexdigest()
            # An interrupted response can be retried without replacing a file or adding an asset twice.
            if destination.exists():
                with destination.open('rb') as f: existing=hashlib.file_digest(f,'sha256').hexdigest()
                if existing != sha: raise ValueError('A different clip already uses this filename; nothing was overwritten.')
            else:
                os.link(partial,destination) # atomic no-overwrite, same filesystem
            video=next((s for s in measured.get('streams',[]) if s.get('codec_type')=='video'),{})
            duration=float(measured.get('format',{}).get('duration',0))
            assets=self.server.engine('/film/projects/' + project + '/assets?type=video_raw')['assets']
            asset=next((a for a in assets if a.get('file_path')==str(destination)),None)
            if asset is None:
                asset=self.server.engine('/film/projects/' + project + '/assets', {
                    'asset_type':'video_raw','file_path':str(destination),'file_name':name,'format':'mov',
                    'mime_type':'video/quicktime','size_bytes':size,'duration_ms':round(duration*1000),
                    'width':video.get('width',0),'height':video.get('height',0),
                    'metadata':{'source':'film-engine-camera','sha256':sha,'slate':metadata}})
            sidecar=destination.with_suffix('.json')
            if not sidecar.exists():
                with sidecar.open('x') as f: json.dump(metadata,f,indent=2)
            self.reply(201, {'asset_id':asset['id'],'project_id':project,'file_path':str(destination),'sha256':sha,'bytes':size})
        except HTTPError as error:
            self.reply(502, {'error':'Film Engine rejected the destination or asset registration. Local footage is retained; retry after checking the project.'})
        except (ValueError, StopIteration) as error:
            self.reply(400, {'error':str(error) or 'Project has no Clips folder.'})
        except Exception as error:
            self.reply(500, {'error':'Transfer could not finish: ' + str(error)})
        finally:
            if partial and os.path.exists(partial): os.unlink(partial)
            self.server.upload_lock.release()
    def log_message(self, fmt, *args):
        # No headers or pairing keys in logs.
        super().log_message(fmt,*args)

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--config',required=True)
    args=parser.parse_args()
    config=json.loads(Path(args.config).read_text())
    if len(config.get('token',''))<24: raise SystemExit('Use a random pairing key of at least 24 characters.')
    server=BridgeServer((config.get('host','0.0.0.0'),config.get('port',5392)),config)
    print('Camera companion listening on port',server.server_port,flush=True)
    server.serve_forever()
