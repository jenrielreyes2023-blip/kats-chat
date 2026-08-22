import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
// ignore: uri_does_not_exist
import 'r2_keys.dart' as keys;

/// Cloudflare R2 Storage via S3-compatible API
/// Credentials via --dart-define or local gitignored r2_keys.dart
class R2StorageService {
  static const String _accountId = String.fromEnvironment('R2_ACCOUNT_ID', defaultValue: '');
  static const String _accessKeyId = String.fromEnvironment('R2_ACCESS_KEY_ID', defaultValue: '');
  static const String _secretAccessKey = String.fromEnvironment('R2_SECRET_ACCESS_KEY', defaultValue: '');
  static const String _bucket = String.fromEnvironment('R2_BUCKET', defaultValue: 'whatsup-uploads');
  static const String _publicUrl = String.fromEnvironment('R2_PUBLIC_URL', defaultValue: '');

  static String get _effectiveAccountId => _accountId.isNotEmpty ? _accountId : _tryKeysAccountId;
  static String get _effectiveAccessKey => _accessKeyId.isNotEmpty ? _accessKeyId : _tryKeysAccessKey;
  static String get _effectiveSecretKey => _secretAccessKey.isNotEmpty ? _secretAccessKey : _tryKeysSecretKey;
  static String get _effectiveBucket => _bucket.isNotEmpty ? _bucket : _tryKeysBucket;
  static String get _effectivePublicUrl => _publicUrl.isNotEmpty ? _publicUrl : _tryKeysPublicUrl;

  static String get _tryKeysAccountId {
    try { return keys.kR2AccountId; } catch (_) { return ''; }
  }
  static String get _tryKeysAccessKey {
    try { return keys.kR2AccessKeyId; } catch (_) { return ''; }
  }
  static String get _tryKeysSecretKey {
    try { return keys.kR2SecretAccessKey; } catch (_) { return ''; }
  }
  static String get _tryKeysBucket {
    try { return keys.kR2Bucket; } catch (_) { return 'whatsup-uploads'; }
  }
  static String get _tryKeysPublicUrl {
    try { return keys.kR2PublicUrl; } catch (_) { return ''; }
  }

  /// Upload file to R2, returns public URL
  static Future<String> uploadFile({
    required File file,
    required String path, // e.g. "images/abc.jpg"
  }) async {
    final bytes = await file.readAsBytes();
    final mimeType = _getMimeType(path);
    
    final now = DateTime.now().toUtc();
    final amzDate = _formatAmzDate(now);
    final dateStamp = _formatDateStamp(now);
    final payloadHash = sha256.convert(bytes).toString();
    
    final host = '$_effectiveAccountId.r2.cloudflarestorage.com';
    final canonicalUri = '/$_effectiveBucket/$path';
    const canonicalQueryString = '';
    final canonicalHeaders = 'host:$host\nx-amz-content-sha256:$payloadHash\nx-amz-date:$amzDate\n';
    const signedHeaders = 'host;x-amz-content-sha256;x-amz-date';
    
    final canonicalRequest = 'PUT\n$canonicalUri\n$canonicalQueryString\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
    final credentialScope = '$dateStamp/auto/s3/aws4_request';
    final stringToSign = 'AWS4-HMAC-SHA256\n$amzDate\n$credentialScope\n${sha256.convert(utf8.encode(canonicalRequest)).toString()}';
    final signingKey = _getSignatureKey(_effectiveSecretKey, dateStamp, 'auto', 's3');
    final signature = _hmacSha256(signingKey, stringToSign).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final authHeader = 'AWS4-HMAC-SHA256 Credential=$_effectiveAccessKey/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature';

    final endpointUrl = Uri.parse('https://$host/$_effectiveBucket/$path');

    final response = await http.put(
      endpointUrl,
      headers: {
        'Authorization': authHeader,
        'x-amz-date': amzDate,
        'x-amz-content-sha256': payloadHash,
        'Content-Type': mimeType,
        'Content-Length': bytes.length.toString(),
        'Host': host,
      },
      body: bytes,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      if (_effectivePublicUrl.isNotEmpty) {
        return '$_effectivePublicUrl/$path';
      }
      return endpointUrl.toString();
    } else {
      throw Exception('R2 upload failed: ${response.statusCode} ${response.body}');
    }
  }

  static String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'mp4': return 'video/mp4';
      case 'mp3': return 'audio/mpeg';
      case 'pdf': return 'application/pdf';
      default: return 'application/octet-stream';
    }
  }

  static String _formatAmzDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4,'0')}${dt.month.toString().padLeft(2,'0')}${dt.day.toString().padLeft(2,'0')}T${dt.hour.toString().padLeft(2,'0')}${dt.minute.toString().padLeft(2,'0')}${dt.second.toString().padLeft(2,'0')}Z';
  }

  static String _formatDateStamp(DateTime dt) {
    return '${dt.year.toString().padLeft(4,'0')}${dt.month.toString().padLeft(2,'0')}${dt.day.toString().padLeft(2,'0')}';
  }

  static List<int> _hmacSha256(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(data)).bytes;
  }

  static List<int> _getSignatureKey(String key, String dateStamp, String region, String service) {
    final kDate = _hmacSha256(utf8.encode('AWS4$key'), dateStamp);
    final kRegion = _hmacSha256(kDate, region);
    final kService = _hmacSha256(kRegion, service);
    final kSigning = _hmacSha256(kService, 'aws4_request');
    return kSigning;
  }
}
