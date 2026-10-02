"""Exercise the armv7 app transport against local TLS 1.2/1.3 servers."""
import hashlib
import http.server
from pathlib import Path
import ssl
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parent.parent
HARNESS = r'''
#import <Foundation/Foundation.h>
#import "LSTransport.h"
int main(int argc, char **argv) { @autoreleasepool {
  NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithUTF8String:argv[1]]] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10];
  r.HTTPMethod=@"POST"; r.HTTPBody=[NSMutableData dataWithLength:215*1024];
  CFAbsoluteTime start=CFAbsoluteTimeGetCurrent();
  for(int attempt=0;attempt<3;attempt++){
  NSURLResponse *response=nil; NSError *error=nil; NSData *body=LSHTTPSRequest(r,[NSString stringWithUTF8String:argv[2]],&response,&error);
  if(!body) { NSLog(@"%@",error); return 1; }
  if([(NSHTTPURLResponse *)response statusCode]!=200 || ![[[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] isEqual:@"received"]) return 2;
  }
  printf("PASS: 3 HTTPS requests, 215 KB each, same cached identity: %.3fs\n",CFAbsoluteTimeGetCurrent()-start);
  return 0;
} }
'''

with tempfile.TemporaryDirectory(prefix='ls-mbedtls-') as td:
    d = Path(td)
    (d/'main.m').write_text(HARNESS)
    inc=ROOT/'vendor/mbedtls-3.6.7'
    subprocess.run(['clang','-fobjc-arc','-DLS_TEST_EXPORT_CLIENT_CERT','-I'+str(ROOT),'-I'+str(inc/'include'),'-I'+str(inc/'library'),'-I'+str(inc/'3rdparty/everest/include'),'-I'+str(inc/'3rdparty/p256-m'),'-I'+str(inc/'3rdparty/p256-m/p256-m'),'-framework','Foundation',str(ROOT/'LSTransport.m'),str(d/'main.m'),'-L/tmp/mbedtls-test/library','-L/tmp/mbedtls-test/3rdparty/everest','-L/tmp/mbedtls-test/3rdparty/p256-m','-lmbedtls','-lmbedx509','-lmbedcrypto','-leverest','-lp256m','-o',str(d/'check')],check=True)
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(d/'key'),'-out',str(d/'cert'),'-days','1','-subj','/CN=LocalSend'],check=True,capture_output=True)
    server_der=subprocess.run(['openssl','x509','-in',str(d/'cert'),'-outform','DER'],check=True,capture_output=True).stdout
    fingerprint=hashlib.sha256(server_der).hexdigest()
    client_der=d/'client.der'; client_pem=d/'client.pem'
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            assert self.connection.getpeercert(binary_form=True)
            assert self.rfile.read(int(self.headers.get('Content-Length',0))) == bytes(215*1024)
            body=b'received'; self.send_response(200); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
        def log_message(self,*args): pass
    class TestServer(http.server.HTTPServer):
        def get_request(self):
            conn, addr = super().get_request()
            import time
            for _ in range(100):
                if client_der.exists(): break
                time.sleep(0.05)
            subprocess.run(['openssl','x509','-inform','DER','-in',str(client_der),'-out',str(client_pem)],check=True,capture_output=True)
            context.load_verify_locations(str(client_pem)); context.verify_mode=ssl.CERT_REQUIRED
            try: return context.wrap_socket(conn,server_side=True),addr
            except Exception as exc: print('TLS server rejected client:',repr(exc)); raise
    for version in (ssl.TLSVersion.TLSv1_2,ssl.TLSVersion.TLSv1_3):
        server=TestServer(('127.0.0.1',0),Handler)
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); context.minimum_version=version; context.maximum_version=version
        client_der.unlink(missing_ok=True)
        context.load_cert_chain(str(d/'cert'),str(d/'key'))
        threading.Thread(target=server.serve_forever,daemon=True).start()
        try: subprocess.run([str(d/'check'),f'https://127.0.0.1:{server.server_port}/api/localsend/v2/prepare-upload',fingerprint],check=True,timeout=20,env={**__import__('os').environ,'LS_TEST_CLIENT_CERT':str(client_der)})
        finally: server.shutdown(); server.server_close()
    print('PASS: TLS 1.2/1.3, pinned server certificate and required self-signed client certificate')
