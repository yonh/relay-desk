import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

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
///
/// When the API fails — most commonly the 60-requests/hour unauthenticated
/// rate limit, which shared egress IPs (CI VMs, corporate NATs) exhaust —
/// the client falls back to the public `github.com` release pages, which are
/// not rate-limited per IP. The fallback recovers tag and asset list but not
/// release notes or SHA-256 digests, so verification degrades to the ZIP
/// signature/structure checks already enforced downstream.
class GithubReleaseClient implements ReleaseClient {
  GithubReleaseClient({
    this.owner = 'yonh',
    this.repo = 'relay-desk',
    HttpClient? client,
    this.timeout = const Duration(seconds: 15),
    @visibleForTesting Uri? apiBase,
    @visibleForTesting Uri? webBase,
  }) : _client = client ?? HttpClient(),
       _apiBase = apiBase ?? Uri.https('api.github.com', ''),
       _webBase = webBase ?? Uri.https('github.com', '');

  final String owner;
  final String repo;
  final HttpClient _client;
  final Duration timeout;
  final Uri _apiBase;
  final Uri _webBase;

  @override
  Future<GithubRelease?> latestRelease() async {
    try {
      return await _latestReleaseViaApi();
    } catch (apiError) {
      // The web path has no per-IP quota; it is only weaker at reporting
      // *why* something failed, so keep the API error when it too fails.
      try {
        return await _latestReleaseViaWeb();
      } catch (_) {
        throw apiError;
      }
    }
  }

  Future<GithubRelease?> _latestReleaseViaApi() async {
    final request = await _client
        .getUrl(
          _apiBase.replace(path: '/repos/$owner/$repo/releases/latest'),
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

  /// Scrapes `github.com` release pages. `/releases/latest` is a 302 to
  /// `/releases/tag/<tag>` — the tag rides the redirect location, which GitHub
  /// only emits for the latest published (non-draft, non-prerelease) release.
  Future<GithubRelease?> _latestReleaseViaWeb() async {
    final request = await _client
        .getUrl(_webBase.replace(path: '/$owner/$repo/releases/latest'))
        .timeout(timeout);
    request.headers.set(HttpHeaders.userAgentHeader, 'relay-desk-updater');
    final response = await request.close().timeout(timeout);
    await response.drain<void>(); // only the redirect URL matters
    if (response.statusCode != 200) {
      throw HttpException(
        'release check failed (${response.statusCode})',
        uri: request.uri,
      );
    }
    String? tag;
    for (final redirect in response.redirects) {
      tag = tagFromReleaseLocation(redirect.location.toString()) ?? tag;
    }
    if (tag == null) return null;
    final version = versionFromTag(tag);
    if (version == null || version.isPreRelease) return null;
    return GithubRelease(
      tag: tag,
      version: version,
      name: tag,
      body: '',
      htmlUrl: '$_webBase/$owner/$repo/releases/tag/$tag',
      prerelease: false,
      draft: false,
      assets: await _assetsViaWeb(tag),
    );
  }

  Future<List<ReleaseAsset>> _assetsViaWeb(String tag) async {
    final request = await _client
        .getUrl(
          _webBase.replace(
            path: '/$owner/$repo/releases/expanded_assets/$tag',
          ),
        )
        .timeout(timeout);
    request.headers.set(HttpHeaders.userAgentHeader, 'relay-desk-updater');
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw HttpException(
        'asset listing failed (${response.statusCode})',
        uri: request.uri,
      );
    }
    final html = await response
        .transform(utf8.decoder)
        .join()
        .timeout(timeout);
    return parseAssetsFromExpandedHtml(
      html: html,
      owner: owner,
      repo: repo,
      tag: tag,
      downloadBase: '$_webBase',
    );
  }

  /// Extracts `v1.2.3` from a `/releases/tag/v1.2.3` URL (path or absolute).
  static String? tagFromReleaseLocation(String location) {
    final match = RegExp(r'/releases/tag/([^/?#]+)').firstMatch(location);
    if (match == null) return null;
    return Uri.decodeComponent(match.group(1)!);
  }

  /// Parses asset links from the `releases/expanded_assets/<tag>` fragment:
  /// anchors like `href="/o/r/releases/download/<tag>/<file>"`. Names arrive
  /// percent-encoded in the href and are decoded for display; the download
  /// URL keeps the encoded form. [downloadBase] is the `scheme://host`
  /// prefix for asset URLs (tests substitute a local server).
  static List<ReleaseAsset> parseAssetsFromExpandedHtml({
    required String html,
    required String owner,
    required String repo,
    required String tag,
    String downloadBase = 'https://github.com',
  }) {
    final pattern = RegExp(
      'href="/${RegExp.escape(owner)}/${RegExp.escape(repo)}'
      '/releases/download/${RegExp.escape(tag)}/([^"?#]+)',
    );
    final assets = <ReleaseAsset>[];
    for (final match in pattern.allMatches(html)) {
      final encoded = match.group(1)!;
      final name = Uri.decodeComponent(encoded);
      if (name.isEmpty || assets.any((a) => a.name == name)) continue;
      assets.add(
        ReleaseAsset(
          name: name,
          downloadUrl:
              '$downloadBase/$owner/$repo/releases/download/'
              '$tag/$encoded',
          size: 0,
        ),
      );
    }
    return assets;
  }
}
