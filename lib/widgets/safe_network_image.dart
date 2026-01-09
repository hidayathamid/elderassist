import 'dart:io';

import 'package:flutter/material.dart';

class _HostReachability {
  static const Duration _timeout = Duration(seconds: 2);
  static const Duration _ttl = Duration(minutes: 5);

  static final Map<String, ({bool reachable, DateTime checkedAt})> _cache = {};
  static final Map<String, Future<bool>> _inFlight = {};

  static Future<bool> canResolve(String host) {
    final trimmedHost = host.trim();
    if (trimmedHost.isEmpty) return Future.value(false);

    final cached = _cache[trimmedHost];
    if (cached != null && DateTime.now().difference(cached.checkedAt) < _ttl) {
      return Future.value(cached.reachable);
    }

    final existing = _inFlight[trimmedHost];
    if (existing != null) return existing;

    final future = InternetAddress.lookup(trimmedHost)
        .timeout(_timeout)
        .then((result) => result.isNotEmpty)
        .catchError((_) => false)
        .then((reachable) {
      _cache[trimmedHost] = (reachable: reachable, checkedAt: DateTime.now());
      _inFlight.remove(trimmedHost);
      return reachable;
    });

    _inFlight[trimmedHost] = future;
    return future;
  }
}

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

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final Widget? placeholder;
  final Widget? errorWidget;
  final bool gaplessPlayback;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = url.trim();
    final uri = Uri.tryParse(trimmedUrl);
    final host = uri?.host ?? '';

    if (trimmedUrl.isEmpty || uri == null || host.isEmpty) {
      return errorWidget ?? placeholder ?? const SizedBox.shrink();
    }

    return FutureBuilder<bool>(
      future: _HostReachability.canResolve(host),
      builder: (context, snapshot) {
        final canResolve = snapshot.data == true;
        if (!canResolve) {
          return placeholder ?? errorWidget ?? const SizedBox.shrink();
        }

        return Image.network(
          trimmedUrl,
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
}

