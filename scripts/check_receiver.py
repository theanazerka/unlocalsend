"""Exercise the actual HTTPS receiver against streamed protocol v2 requests."""
import hashlib
import http.client
import json
import os
from pathlib import Path
import ssl
import subprocess
import tempfile
import time
import socket
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parent.parent
HARNESS = r'''
#import "LSReceiver.h"
#import "LSTLSIdentity.h"
int main(int argc,char **argv){@autoreleasepool{
 LSReceiver *receiver=[[LSReceiver alloc] init];receiver.port=0;receiver.alias=@"Test iPhone";receiver.documentsPath=[NSString stringWithUTF8String:argv[1]];
 receiver.eventHandler=^(NSDictionary *state){if([state[@"phase"] isEqual:@"offer"]){NSString *sender=state[@"sender"];if([sender isEqual:@"Wait"])return;[receiver respond:![sender isEqual:@"Decline"]];}};
 [receiver start:^(NSError *error){if(error){fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);exit(1);}NSData *d=[NSJSONSerialization dataWithJSONObject:[receiver deviceInfo] options:0 error:nil];printf("%s\n",[[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] UTF8String]);fflush(stdout);}];
 [[NSRunLoop currentRunLoop] run];
}}
'''
with tempfile.TemporaryDirectory(prefix='localsend-receiver-') as folder:
    temp = Path(folder)
    (temp/'main.m').write_text(HARNESS)
    inc = ROOT/'vendor/mbedtls-3.6.7'
    compile_command=['clang','-O2','-fobjc-arc','-Wno-deprecated-declarations','-Wno-arc-retain-cycles','-DLS_TEST_EXPORT_CLIENT_CERT','-I'+str(ROOT),'-I'+str(inc/'include'),'-framework','Foundation',str(ROOT/'LSReceiver.m'),str(ROOT/'LSTransport.m'),str(temp/'main.m'),'-L/tmp/mbedtls-test/library','-L/tmp/mbedtls-test/3rdparty/everest','-L/tmp/mbedtls-test/3rdparty/p256-m','-lmbedtls','-lmbedx509','-lmbedcrypto','-leverest','-lp256m','-o',str(temp/'server')]
    subprocess.run(compile_command,check=True)
    (temp/'client.m').write_text(r'''
#import "LSTransport.h"
int main(int argc,char **argv){@autoreleasepool{
 NSString *base=[NSString stringWithFormat:@"https://127.0.0.1:%s/api/localsend/v2",argv[1]];
 NSString *pin=[NSString stringWithUTF8String:argv[2]];NSData *payload=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[3]]];
 NSDictionary *metadata=@{@"info":@{@"alias":@"Native client"},@"files":@{@"id":@{@"id":@"id",@"fileName":@"Native.bin",@"size":@(payload.length),@"fileType":@"application/octet-stream"}}};
 NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:[base stringByAppendingString:@"/prepare-upload"]]];r.HTTPMethod=@"POST";r.HTTPBody=[NSJSONSerialization dataWithJSONObject:metadata options:0 error:nil];
 NSURLResponse *response=nil;NSError *error=nil;CFAbsoluteTime start=CFAbsoluteTimeGetCurrent();
 NSData *answer=LSHTTPSRequest(r,pin,&response,&error);if(!answer || [(NSHTTPURLResponse *)response statusCode]!=200){NSLog(@"%@",error);return 1;}
 NSDictionary *session=[NSJSONSerialization JSONObjectWithData:answer options:0 error:nil];
 r=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/upload?sessionId=%@&fileId=id&token=%@",base,session[@"sessionId"],session[@"files"][@"id"]]]];r.HTTPMethod=@"POST";r.HTTPBody=payload;
 answer=LSHTTPSRequest(r,pin,&response,&error);if(!answer || [(NSHTTPURLResponse *)response statusCode]!=200){NSLog(@"%@",error);return 2;}
 printf("PASS: native client → native receiver, 215 KB: %.3fs\n",CFAbsoluteTimeGetCurrent()-start);return 0;
}}
''')
    subprocess.run([str(temp/'client.m') if c==str(temp/'main.m') else str(temp/'client') if c==str(temp/'server') else c for c in compile_command],check=True)
    process = subprocess.Popen([str(temp/'server'),folder],stdout=subprocess.PIPE,text=True)
    try:
        info=json.loads(process.stdout.readline())
        context=ssl._create_unverified_context()
        context.minimum_version=ssl.TLSVersion.TLSv1_2
        def req(path,body=b'',headers=None,chunked=False):
            c=http.client.HTTPSConnection('127.0.0.1',info['port'],context=context,timeout=5)
            c.connect()
            assert hashlib.sha256(c.sock.getpeercert(binary_form=True)).hexdigest().upper()==info['fingerprint']
            c.request('POST',path,body=body,headers=headers or {},encode_chunked=chunked)
            response=c.getresponse(); data=response.read();status=response.status;c.close()
            return status,json.loads(data) if data else None
        def offer(files,sender='Sender'):
            return req('/api/localsend/v2/prepare-upload',json.dumps({'info':{'alias':sender,'deviceModel':'iPhone'},'files':files}).encode(),{'Content-Type':'application/json'})
        def metadata(name,data,checksum=True):
            d={'id':'id','fileName':name,'size':len(data),'fileType':'application/octet-stream'}
            if checksum:d['sha256']=hashlib.sha256(data).hexdigest()
            return d
        def path(session,fid='id',token=None):
            return '/api/localsend/v2/upload?'+urlencode({'sessionId':session['sessionId'],'fileId':fid,'token':token or session['files'][fid]})
        payload=os.urandom(215*1024);started=time.monotonic()
        status,session=offer({'id':metadata('Photo.jpg',payload)})
        assert status==200
        assert req(path(session,token='wrong'),b'')[0]==403
        assert offer({'id':metadata('busy.bin',b'')})[0]==409
        assert req(path(session),payload)[0]==200
        assert (temp/'Photo.jpg').read_bytes()==payload
        print(f'PASS: pinned HTTPS, accepted offer, token validation, busy session, 215 KB streamed in {time.monotonic()-started:.2f}s')
        # A second same-name upload must preserve the first file.
        status,session=offer({'id':metadata('Photo.jpg',payload)})
        chunks=(payload[i:i+7777] for i in range(0,len(payload),7777))
        assert req(path(session),chunks,{'Content-Type':'application/octet-stream'},True)[0]==200
        assert (temp/'Photo (1).jpg').read_bytes()==payload
        print('PASS: chunked transfer and collision-safe filenames')
        assert offer({'id':metadata('declined.bin',b'abc')},'Decline')[0]==403
        assert not (temp/'declined.bin').exists()
        status,session=offer({'id':metadata('bad.bin',b'good')})
        assert req(path(session),b'evil')[0]==422
        assert not (temp/'bad.bin').exists()
        assert not list(temp.glob('.incoming-*'))
        print('PASS: rejection, checksum mismatch, temporary file cleanup')
        status,session=offer({'id':metadata('../safe.bin',b'abc')})
        assert req('/api/localsend/v2/cancel?'+urlencode({'sessionId':session['sessionId']}))[0]==200
        assert req(path(session),b'')[0]==403
        print('PASS: cancellation invalidates upload tokens')
        status,session=offer({'id':metadata('interrupted.bin',payload)})
        stalled=context.wrap_socket(socket.create_connection(('127.0.0.1',info['port'])),server_hostname='localhost')
        header=f'POST {path(session)} HTTP/1.1\r\nHost: localhost\r\nContent-Length: {len(payload)}\r\n\r\n'
        stalled.sendall(header.encode()+payload[:1024])
        for _ in range(100):
            if list(temp.glob('.incoming-*')):break
            time.sleep(.01)
        assert req('/api/localsend/v2/cancel?'+urlencode({'sessionId':session['sessionId']}))[0]==200
        stalled.close()
        for _ in range(100):
            if not list(temp.glob('.incoming-*')):break
            time.sleep(.01)
        assert not (temp/'interrupted.bin').exists() and not list(temp.glob('.incoming-*'))
        print('PASS: cancellation interrupts a stalled upload and removes its partial file')

        status,session=offer({'a':{'id':'a',**metadata('a.txt',b'aa')},'b':{'id':'b',**metadata('b.txt',b'bbb')}})
        assert req(path(session,'a'),b'aa')[0]==200
        assert req(path(session,'b'),b'bbb')[0]==200
        assert (temp/'a.txt').read_bytes()==b'aa' and (temp/'b.txt').read_bytes()==b'bbb'
        status,session=offer({'id':metadata('empty.txt',b'')})
        assert req(path(session),b'')[0]==200 and (temp/'empty.txt').read_bytes()==b''
        print('PASS: multiple files and zero-byte file')
        (temp/'payload.bin').write_bytes(payload)
        subprocess.run([str(temp/'client'),str(info['port']),info['fingerprint'],str(temp/'payload.bin')],check=True,timeout=10)
        assert (temp/'Native.bin').read_bytes()==payload

    finally:
        process.terminate();process.wait(timeout=5)
