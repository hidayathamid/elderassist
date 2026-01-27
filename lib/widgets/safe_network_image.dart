import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class SafeNetworkImage extends StatelessWidget {
  const SafeNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.placeholder,
    this.errorWidget,
    this.gaplessPlayback = true,
  });

  static const int _firebaseStorageMaxBytes = 5 * 1024 * 1024;
  static final Map<String, Future<Uint8List?>> _firebaseStorageInFlight = {};
  static final Map<String, Uint8List> _firebaseStorageCache = {};

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final Widget? placeholder;
  final Widget? errorWidget;
  final bool gaplessPlayback;

  bool _isFirebaseStorageUrl(Uri uri) =>
      uri.host.toLowerCase().contains('firebasestorage.googleapis.com');

  bool _isGsUrl(Uri uri) => uri.scheme.toLowerCase() == 'gs';

  Future<Uint8List?> _loadFirebaseStorageBytes(String trimmedUrl) {
    final cached = _firebaseStorageCache[trimmedUrl];
    if (cached != null) return Future.value(cached);

    final existing = _firebaseStorageInFlight[trimmedUrl];
    if (existing != null) return existing;

    final future = () async {
      try {
        final ref = FirebaseStorage.instance.refFromURL(trimmedUrl);
        final bytes = await ref.getData(_firebaseStorageMaxBytes);
        if (bytes != null) _firebaseStorageCache[trimmedUrl] = bytes;
        return bytes;
      } catch (_) {
        return null;
      } finally {
        _firebaseStorageInFlight.remove(trimmedUrl);
      }
    }();

    _firebaseStorageInFlight[trimmedUrl] = future;
    return future;
  }

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = url.trim();
    final uri = Uri.tryParse(trimmedUrl);

    if (trimmedUrl.isEmpty || uri == null) {
      return errorWidget ?? placeholder ?? const SizedBox.shrink();
    }

    // Prefer plain HTTPS loading for download URLs (firebasestorage.googleapis.com).
    // Using FirebaseStorage.refFromURL() may fail in debug/test environments due to
    // App Check / auth preconditions, even though the download URL is valid.
    if (_isFirebaseStorageUrl(uri) || uri.scheme.toLowerCase().startsWith('http')) {
      return Image.network(
        trimmedUrl,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        gaplessPlayback: gaplessPlayback,
        errorBuilder: (context, error, stackTrace) {
          if (kDebugMode) {
            debugPrint('SafeNetworkImage failed: $trimmedUrl');
            debugPrint('SafeNetworkImage error: $error');
          }
          return errorWidget ?? placeholder ?? const SizedBox.shrink();
        },
      );
    }

    // Support gs:// URLs by fetching bytes via Firebase Storage SDK.
    if (_isGsUrl(uri)) {
      return FutureBuilder<Uint8List?>(
        future: _loadFirebaseStorageBytes(trimmedUrl),
        builder: (context, bytesSnapshot) {
          final bytes = bytesSnapshot.data;
          if (bytes == null || bytes.isEmpty) {
            if (bytesSnapshot.connectionState == ConnectionState.waiting) {
              return placeholder ?? const SizedBox.shrink();
            }
            return errorWidget ?? placeholder ?? const SizedBox.shrink();
          }
          return Image.memory(
            bytes,
            width: width,
            height: height,
            fit: fit,
            alignment: alignment,
            gaplessPlayback: gaplessPlayback,
            errorBuilder: (context, error, stackTrace) {
              return errorWidget ?? placeholder ?? const SizedBox.shrink();
            },
          );
        },
      );
    }

    return errorWidget ?? placeholder ?? const SizedBox.shrink();
  }
}
