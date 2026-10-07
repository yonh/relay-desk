import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/update/models.dart';

/// Source of "what is the latest release". Interface so tests inject fakes.
abstract class ReleaseClient {
  /// Returns the latest non-draft, non-prerelease release, or `null` when
  /// none qualifies (e.g. the newest tag is a prerelease).
  Future<GithubRelease?> latestRelease();
}

/// Talks to `api.github.com` with `dart:io` — no `http` dependency needed.
/// Redirects are followed automatically (asset downloads land on a signed
/// CDN URL after a 302).
class GithubReleaseClient implements ReleaseClient {
  GithubReleaseClient({
    this.owner = 'yonh',
    this.repo = 'relay-desk',
    HttpClient? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? HttpClient();

  final String owner;
  final String repo;
  final HttpClient _client;
  final Duration timeout;

  @override
  Future<GithubRelease?> latestRelease() async {
    final request = await _client
        .getUrl(
          Uri.https('api.github.com', '/repos/$owner/$repo/releases/latest'),
        )
        .timeout(timeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    request.headers.set(HttpHeaders.userAgentHeader, 'relay-desk-updater');
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw HttpException(
        'release check failed (${response.statusCode})',
        uri: request.uri,
      );
    }
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(timeout);
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    return GithubRelease.fromJson(decoded);
  }
}
