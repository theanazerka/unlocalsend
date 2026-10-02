# LocalSend 6

A LocalSend client for iOS 6, built with Theos. Supports device discovery over UDP multicast, sending files over HTTP / HTTPS, and receiving files through the LocalSend v2 HTTPS API.

## Features

- Full iPhone 5 / 5s screen height (320×568), with launch images for iOS 6 and later.
- UIKit / QuartzCore interface with tabs, cards, light and dark themes, and three accent colors.
- Photo and video selection, text sharing, and an iOS 6 file browser starting at `/`, with hidden files, a Documents shortcut, and manual path entry. Access to protected files depends on the app's permissions.
- Russian, English, and Ukrainian interfaces. Settings → Language offers manual selection and System (the default). Unsupported languages fall back to English.
- Images and compatible videos are automatically saved to Photos. Videos the system can decode are converted to H.264/AAC 480p when necessary. Older iOS versions cannot decode HEVC/H.265; the original remains in the app.
- The Info button on the Receive tab shows the device name, all active IPv4/IPv6 addresses and their interfaces, HTTPS/TCP and UDP ports, and listener status.
- Icon labels on the Send tab use explicit layout frames; manual IP entry opens through a separate button.
- The device name, animation preference, and history of the last ten successful transfers persist between launches.
- HTTPS receiving with Accept / Decline confirmation, progress, details, cancellation, and multiple files. Incoming data is written to disk in chunks; both Content-Length and chunked transfer encoding are supported.
- Verifies the supplied SHA-256 checksum and removes temporary files on failure or cancellation. Conflicting filenames receive a numeric suffix.
- The logo on the Receive tab rotates smoothly clockwise, completing one turn every 25 seconds. The Animations setting disables rotation.
- Listens for multicast traffic at `224.0.0.167:53317` and responds to LocalSend announcements.
- Displays discovered devices and supports manual IP entry.
- Sends files from the app's `Documents` folder through `prepare-upload` and `upload`.
- Exposes the `Documents` folder through iTunes File Sharing.

## Building

Install Theos and the iOS 6 SDK, then run:

```sh
make package FINALPACKAGE=1 DEBUG=0
```

The package is created in `packages/`. The build uses the iPhoneOS6.1 SDK and targets iOS 6.0 or later. After building, run `python3 scripts/package_ipa.py` to create an IPA.

## Usage

1. Install the package on a jailbroken device and connect both devices to the same Wi-Fi network.
2. Keep LocalSend open on the receiving device. There is no need to disable encryption: the client uses the protocol announced by the device.
3. Copy files into the app through iTunes → device → Apps → File Sharing → LocalSend 6.
4. On the Send tab, select a photo, text, or file, then tap the recipient's card. When entering an IP address manually, tap Send.
5. The File button opens a browser starting at `/`. My files opens Documents; external files are copied into the app before sending. Ripple effects and tab bar animations are disabled. The smooth switch animation and logo rotation are controlled by the Animations setting.

Outgoing HTTPS uses the bundled Mbed TLS 3.6.7 library with TLS 1.2 / 1.3 and an ECDSA P-256 certificate generated once on the device. The certificate and private key are stored in `Library/LocalSendIdentity`, outside Documents / File Sharing, and reused. This avoids regenerating an RSA key before every request. Incoming HTTPS supports TLS 1.2, listens on TCP port 53317, and handles `/info`, `/register`, `/prepare-upload`, `/upload`, and `/cancel`. During the handshake, the recipient's certificate fingerprint is checked against the fingerprint in its LocalSend announcement. When an IP address is entered manually without an announcement, the fingerprint is not checked. For iOS 6 compatibility, the monotonic clock uses `mach_absolute_time`. Devices announcing HTTP are handled through `NSURLConnection`. The latest transfer error is saved to `Documents/LastTransferError.txt`. Outgoing files are loaded entirely into memory, so small files are recommended for older devices.

The supplied SVG logo is stored in `Resources/localsend.svg` and drawn using vector curves in `LSDesign.m`. Interface icons are drawn with UIKit; SwiftUI and SF Symbols are not used.

## Receiving

Keep the app open, select this iPhone on the other device, and send files. Confirm the request by tapping Accept. Once the transfer finishes, tap a file on the receiving screen to preview it and access the export menu. Files are also available through File and iTunes File Sharing.

Images and compatible videos are automatically saved to the system photo library through AssetsLibrary. H.264 MP4/MOV files are saved without conversion when the system accepts the original. Other videos the system can decode are exported through AVFoundation as H.264/AAC at 640×480. HEVC/H.265, unsupported codecs, and export failures do not cause the original to be deleted: the app displays a save error.

HEIC / HEIF images are converted to JPEG using the bundled libheif + libde265 libraries, while the original remains in Documents. Conversion is limited to 24 megapixels for older devices. Larger originals remain in the app, with a conversion error message.

Allow access to Photos when saving for the first time. If access is denied, enable it under Settings → Privacy → Photos. Auto-lock is disabled while waiting for confirmation, transferring files, or processing the media save queue, and restored when processing finishes. Background receiving is not supported.

## Interface Resources

The app icon source is `Assets/AppIcon.png`, with 57/114/120 px versions in `Resources`. Translation tables are stored in `Assets/Translations.tsv`; `python3 scripts/build_localizations.py` regenerates the `ru/en/uk.lproj` resources. Language changes take effect immediately and persist between launches.

## Checks

`python3 scripts/check_mbedtls.py` checks outgoing TLS 1.2 / 1.3 with server certificate pinning and a required client certificate, using three requests with 215 KB payloads in one process.

`python3 scripts/check_receiver.py` checks HTTPS receiving, acceptance and rejection, chunked transfer encoding, tokens, busy state, checksums, conflicting filenames, multiple files, an empty file, cancellation of an active upload, and sending from the native transport to the native receiver.

`python3 scripts/check_heic.py` checks the C decoding bridge with a libheif HEIC sample and an Apple HEIC file, valid JPEG output, and rejection of a corrupt file. It uses native test libraries in `/tmp/localsend-heic-mac`; the armv7 libraries can be rebuilt with `build_heic.py`.

Saving through AssetsLibrary and photo library permissions require testing on a device. The tests run on a Mac against temporary local servers; performance on an older iPhone has not been measured.

Official specification: [LocalSend Protocol v2](https://github.com/localsend/protocol).
