"""Host integration check: native RSA identity, certificate pinning and required client auth.

Uses an isolated temporary macOS keychain; never changes the default keychain.
"""
import hashlib
import http.server
import json
from pathlib import Path
import ssl
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parent.parent
HARNESS = r'''
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "LSIdentity.h"
#import "LSConnection.h"
@interface TestConnection : LSConnection
@property (nonatomic, strong) NSURLCredential *credential;
@end
@implementation TestConnection
- (NSURLCredential *)clientCredentialWithError:(NSError **)error { return self.credential; }
@end
int main(int argc, char **argv) { @autoreleasepool {
    NSString *folder = [NSString stringWithUTF8String:argv[1]];
    if (argc == 2) {
        SecKeyRef pub = NULL, priv = NULL;
        NSDictionary *params = @{(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeRSA,(__bridge id)kSecAttrKeySizeInBits:@2048};
        if (SecKeyGeneratePair((__bridge CFDictionaryRef)params,&pub,&priv)) return 1;
        NSData *pubDER = CFBridgingRelease(SecKeyCopyExternalRepresentation(pub,NULL));
        NSData *privDER = CFBridgingRelease(SecKeyCopyExternalRepresentation(priv,NULL));
        NSError *error = nil; NSData *cert = LSCreateCertificate(priv,pubDER,&error);
        BOOL ok = [cert writeToFile:[folder stringByAppendingPathComponent:@"client.der"] atomically:YES] && [privDER writeToFile:[folder stringByAppendingPathComponent:@"private.der"] atomically:YES];
        CFRelease(pub); CFRelease(priv); if (!ok) NSLog(@"%@",error); return ok ? 0 : 2;
    }
    NSString *keychainPath = [folder stringByAppendingPathComponent:@"test.keychain"];
    SecKeychainRef keychain = NULL;
    OSStatus status = SecKeychainCreate(keychainPath.fileSystemRepresentation,4,"test",false,NULL,&keychain);
    if (status) return 3;
    NSData *p12 = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"client.p12"]];
    CFArrayRef items = NULL;
    status = SecPKCS12Import((__bridge CFDataRef)p12,(__bridge CFDictionaryRef)@{(__bridge id)kSecImportExportPassphrase:@"test",(__bridge id)kSecImportExportKeychain:(__bridge id)keychain},&items);
    if (status) { SecKeychainDelete(keychain); CFRelease(keychain); return 4; }
    NSArray *identities = CFBridgingRelease(items);
    SecIdentityRef identity = (__bridge SecIdentityRef)[identities[0] objectForKey:(__bridge id)kSecImportItemIdentity];
    SecCertificateRef cert = NULL; SecIdentityCopyCertificate(identity,&cert);
    TestConnection *client = [TestConnection new];
    client.credential = [NSURLCredential credentialWithIdentity:identity certificates:@[(__bridge id)cert] persistence:NSURLCredentialPersistenceForSession];
    CFRelease(cert); client.expectedFingerprint = [NSString stringWithUTF8String:argv[3]];
    int result = 0;
    for (NSString *path in @[@"prepare-upload", @"upload"]) {
        NSString *url = [NSString stringWithFormat:@"%s/api/localsend/v2/%@",argv[2],path];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:5];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [[path isEqual:@"prepare-upload"] ? @"{\"files\":{\"file\":{\"size\":10}}}" : @"photo-data" dataUsingEncoding:NSUTF8StringEncoding];
        NSURLResponse *response = nil; NSError *error = nil;
        NSData *data = [client sendRequest:request response:&response error:&error];
        if (argc > 4) {
            result = (error && error.code == NSURLErrorServerCertificateUntrusted) ? 0 : 6; break;
        }
        if (error || !data || [(NSHTTPURLResponse *)response statusCode] != 200) { NSLog(@"HTTPS failed: %@",error); result = 5; break; }
    }
    SecKeychainDelete(keychain); CFRelease(keychain); return result;
} }
'''


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


class Handler(http.server.BaseHTTPRequestHandler):
    transfers = []

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        assert self.connection.getpeercert(binary_form=True), "client certificate missing"
        if self.path.endswith("prepare-upload"):
            assert json.loads(body)["files"]["file"]["size"] == 10
            reply = b'{"sessionId":"test","files":{"file":"token"}}'
        else:
            assert body == b"photo-data"
            reply = b""
        self.transfers.append(self.path)
        self.send_response(200)
        self.send_header("Content-Length", str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)

    def log_message(self, *args):
        pass


with tempfile.TemporaryDirectory(prefix="localsend-mtls-") as folder:
    d = Path(folder)
    (d / "main.m").write_text(HARNESS)
    run("clang", "-fobjc-arc", "-Wno-deprecated-declarations", "-framework", "Foundation", "-framework", "Security", "-I", str(ROOT), str(ROOT / "LSIdentity.m"), str(ROOT / "LSConnection.m"), str(d / "main.m"), "-o", str(d / "check"))
    run(str(d / "check"), folder)
    run("openssl", "x509", "-inform", "DER", "-in", str(d / "client.der"), "-out", str(d / "client.pem"))
    run("openssl", "rsa", "-inform", "DER", "-in", str(d / "private.der"), "-out", str(d / "client-key.pem"), capture_output=True)
    run("openssl", "verify", "-CAfile", str(d / "client.pem"), str(d / "client.pem"))
    run("openssl", "pkcs12", "-export", "-in", str(d / "client.pem"), "-inkey", str(d / "client-key.pem"), "-out", str(d / "client.p12"), "-passout", "pass:test", "-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES", "-macalg", "sha1", capture_output=True)
    run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", str(d / "server-key.pem"), "-out", str(d / "server.pem"), "-days", "1", "-subj", "/CN=LocalSend", capture_output=True)
    serverDER = run("openssl", "x509", "-in", str(d / "server.pem"), "-outform", "DER", capture_output=True).stdout
    fingerprint = hashlib.sha256(serverDER).hexdigest()
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ctx.maximum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(str(d / "server.pem"), str(d / "server-key.pem"))
    ctx.load_verify_locations(str(d / "client.pem"))
    ctx.verify_mode = ssl.CERT_REQUIRED
    for expected, extra in ((fingerprint, []), ("00" * 32, ["reject"])):
        server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        server.socket = ctx.wrap_socket(server.socket, server_side=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            run(str(d / "check"), folder, f"https://127.0.0.1:{server.server_port}", expected, *extra, timeout=20)
        finally:
            server.shutdown()
            server.server_close()
    assert len(Handler.transfers) == 2, Handler.transfers
    print("PASS: self-signed client identity, mutual TLS 1.2 prepare/upload and certificate mismatch rejection")
