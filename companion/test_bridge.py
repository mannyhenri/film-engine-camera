import base64, importlib.util, json, tempfile, threading, unittest
from pathlib import Path
from urllib.request import Request,urlopen
from urllib.error import HTTPError
from unittest.mock import patch
import bridge

class TransferTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.folder=Path(self.temp.name)
        self.assets=[]; self.project='12345678-1234-4234-8234-123456789abc'
        self.server=bridge.BridgeServer(('127.0.0.1',0),{'token':'test-key-abcdefghijklmnopqrstuvwxyz','engine_url':'http://unused'})
        def engine(path,body=None):
            if path.endswith('/storage'): return {'folders':[{'subdir':'video','path':str(self.folder)}]}
            if '/assets' in path:
                if body: self.assets.append(dict(body,id='asset-1')); return self.assets[-1]
                return {'assets':self.assets}
            return {'projects':[{'id':self.project,'title':'Test'}]}
        self.server.engine=engine
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True); self.thread.start()
    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.temp.cleanup()
    def request(self,path,body=None,token=True):
        headers={'Authorization':'Bearer test-key-abcdefghijklmnopqrstuvwxyz'} if token else {}
        req=Request('http://127.0.0.1:'+str(self.server.server_port)+path,data=body,method='PUT' if body is not None else 'GET',headers=headers)
        with urlopen(req) as response: return json.load(response)
    def test_auth_and_projects(self):
        with self.assertRaises(HTTPError) as result: self.request('/projects',token=False)
        self.assertEqual(result.exception.code,401)
        self.assertEqual(self.request('/projects')['projects'][0]['title'],'Test')
    def test_reject_path_traversal(self):
        with self.assertRaises(HTTPError): self.request('/projects/'+self.project+'/clips/../../bad.mov',b'bad')
        self.assertEqual(list(self.folder.iterdir()),[])
    def test_invalid_movie_leaves_no_partial_or_asset(self):
        with self.assertRaises(HTTPError): self.request('/projects/'+self.project+'/clips/FEC-12345678-1234-4234-8234-123456789abc.mov',b'not a movie at all')
        self.assertEqual(self.assets,[]); self.assertEqual(list(self.folder.iterdir()),[])
    def test_stream_register_retry_and_no_overwrite(self):
        name='FEC-12345678-1234-4234-8234-123456789abc.mov'; path='/projects/'+self.project+'/clips/'+name
        payload=b'\x00\x00\x00\x14ftypqt  '+b'x'*1000
        probe=type('Result',(),{'returncode':0,'stdout':b'{"streams":[{"codec_type":"video","width":1920,"height":1080}],"format":{"duration":"1"}}'})()
        with patch('bridge.subprocess.run',return_value=probe):
            result=self.request(path,payload); retry=self.request(path,payload)
            self.assertEqual(result['sha256'],retry['sha256']); self.assertEqual(len(self.assets),1)
            with self.assertRaises(HTTPError): self.request(path,payload+b'changed')
        self.assertEqual((self.folder/name).read_bytes(),payload)
        self.assertEqual(list(self.folder.glob('*.part')),[])
        self.assertTrue((self.folder/name).with_suffix('.json').exists())
if __name__=='__main__': unittest.main()
