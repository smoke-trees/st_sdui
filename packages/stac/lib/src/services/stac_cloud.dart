import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:stac/src/framework/stac_service.dart';
import 'package:stac/src/models/stac_artifact_type.dart';
import 'package:stac/src/models/stac_cache.dart';
import 'package:stac/src/models/stac_cache_config.dart';
import 'package:stac/src/services/stac_cache_service.dart';
import 'package:stac_logger/stac_logger.dart';

/// Service for fetching screens from Stac Cloud with caching support.
///
/// This service automatically caches screens and compares versions
/// to avoid unnecessary network requests.
///
class StacCloud {
  const StacCloud._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  static String _baseUrl = '';

  /// Sets the base URL for Stac Cloud API requests.
  static void setBaseUrl(String url) {
    _baseUrl = url;
  }

  /// Gets the fetch URL for a given artifact type.
  static String _getFetchUrl(StacArtifactType artifactType) {
    switch (artifactType) {
      case StacArtifactType.screen:
        return '$_baseUrl/app-screens';
      case StacArtifactType.theme:
        return '$_baseUrl/app-themes';
    }
  }

  /// Gets the response field containing the artifact JSON.
  static String _getJsonFieldName(StacArtifactType artifactType) {
    switch (artifactType) {
      case StacArtifactType.screen:
        return 'screenJson';
      case StacArtifactType.theme:
        return 'themeJson';
    }
  }

  /// Compares semantic versions such as `1.0.0` and `1.0.0-beta.1`.
  ///
  /// This intentionally supports the existing numeric cache entries as well,
  /// so a numeric version is treated as `major.0.0`.
  static int _compareVersions(String left, String right) {
    final leftParts = _parseVersion(left);
    final rightParts = _parseVersion(right);

    for (var i = 0; i < 3; i++) {
      final comparison = leftParts.core[i].compareTo(rightParts.core[i]);
      if (comparison != 0) return comparison;
    }

    if (leftParts.preRelease == rightParts.preRelease) return 0;
    if (leftParts.preRelease.isEmpty) return 1;
    if (rightParts.preRelease.isEmpty) return -1;
    return leftParts.preRelease.compareTo(rightParts.preRelease);
  }

  static ({List<int> core, String preRelease}) _parseVersion(String version) {
    final withoutBuild = version.split('+').first;
    final separator = withoutBuild.indexOf('-');
    final core = separator == -1
        ? withoutBuild
        : withoutBuild.substring(0, separator);
    final preRelease = separator == -1
        ? ''
        : withoutBuild.substring(separator + 1);
    final parts = core
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return (core: parts.take(3).toList(), preRelease: preRelease);
  }

  /// Gets the query parameter name for a given artifact type.
  static String _getQueryParamName(StacArtifactType artifactType) {
    switch (artifactType) {
      case StacArtifactType.screen:
        return 'screenName';
      case StacArtifactType.theme:
        return 'themeName';
    }
  }

  /// Tracks artifacts currently being fetched in background to prevent duplicates.
  static final Map<StacArtifactType, Set<String>> _backgroundFetchInProgress = {
    StacArtifactType.screen: {},
    StacArtifactType.theme: {},
  };

  /// Fetches an artifact from Stac Cloud with intelligent caching.
  ///
  /// Uses the global cache configuration from [StacService.defaultCacheConfig],
  /// which is set via [Stac.initialize].
  ///
  static Future<Response?> _fetchArtifact({
    required StacArtifactType artifactType,
    required String artifactName,
  }) async {
    final cacheConfig = StacService.defaultCacheConfig;

    // Handle network-only strategy
    if (cacheConfig.strategy == StacCacheStrategy.networkOnly) {
      return _fetchArtifactFromNetwork(
        artifactType: artifactType,
        artifactName: artifactName,
        saveToCache: false,
      );
    }

    // Get cached artifact
    final cachedArtifact = await StacCacheService.getCachedArtifact(
      artifactName,
      artifactType,
    );

    // Handle cache-only strategy
    if (cacheConfig.strategy == StacCacheStrategy.cacheOnly) {
      if (cachedArtifact != null) {
        return _buildArtifactCacheResponse(artifactType, cachedArtifact);
      }
      throw Exception(
        'No cached data available for $artifactType $artifactName (cache-only mode)',
      );
    }

    // Check if cache is valid based on maxAge (sync to avoid double cache read)
    final isCacheValid = StacCacheService.isCacheValid(
      cachedArtifact,
      cacheConfig.maxAge,
    );

    // Handle different strategies
    switch (cacheConfig.strategy) {
      case StacCacheStrategy.networkFirst:
        return _handleArtifactNetworkFirst(
          artifactType: artifactType,
          artifactName: artifactName,
          cachedArtifact: cachedArtifact,
        );

      case StacCacheStrategy.cacheFirst:
        return _handleArtifactCacheFirst(
          artifactType: artifactType,
          artifactName: artifactName,
          cachedArtifact: cachedArtifact,
          isCacheValid: isCacheValid,
          config: cacheConfig,
        );

      case StacCacheStrategy.optimistic:
        return _handleArtifactOptimistic(
          artifactType: artifactType,
          artifactName: artifactName,
          cachedArtifact: cachedArtifact,
          isCacheValid: isCacheValid,
          config: cacheConfig,
        );

      case StacCacheStrategy.cacheOnly:
      case StacCacheStrategy.networkOnly:
        // Already handled above
        return _fetchArtifactFromNetwork(
          artifactType: artifactType,
          artifactName: artifactName,
          saveToCache: false,
        );
    }
  }

  /// Fetches a screen from Stac Cloud with intelligent caching.
  ///
  /// Uses the global cache configuration from [StacService.defaultCacheConfig],
  /// which is set via [Stac.initialize].
  static Future<Response?> fetchScreen({required String routeName}) async {
    return _fetchArtifact(
      artifactType: StacArtifactType.screen,
      artifactName: routeName,
    );
  }

  /// Handles network-first strategy: Try network, fallback to cache.
  static Future<Response?> _handleArtifactNetworkFirst({
    required StacArtifactType artifactType,
    required String artifactName,
    StacCache? cachedArtifact,
  }) async {
    try {
      return await _fetchArtifactFromNetwork(
        artifactType: artifactType,
        artifactName: artifactName,
        saveToCache: true,
      );
    } catch (e) {
      // Network failed, use cache as fallback
      if (cachedArtifact != null) {
        Log.d(
          'StacCloud: Network failed, using cached data for ${artifactType.name} $artifactName',
        );
        return _buildArtifactCacheResponse(artifactType, cachedArtifact);
      }
      rethrow;
    }
  }

  /// Handles cache-first strategy: Use valid cache, fallback to network.
  static Future<Response?> _handleArtifactCacheFirst({
    required StacArtifactType artifactType,
    required String artifactName,
    StacCache? cachedArtifact,
    required bool isCacheValid,
    required StacCacheConfig config,
  }) async {
    // If cache is valid and exists, use it
    if (cachedArtifact != null && isCacheValid) {
      // Optionally refresh in background
      if (config.refreshInBackground) {
        _fetchAndUpdateArtifactInBackground(
          artifactType: artifactType,
          artifactName: artifactName,
          cachedVersion: cachedArtifact.version,
        );
      }
      return _buildArtifactCacheResponse(artifactType, cachedArtifact);
    }

    // Cache invalid or doesn't exist, fetch from network
    try {
      return await _fetchArtifactFromNetwork(
        artifactType: artifactType,
        artifactName: artifactName,
        saveToCache: true,
      );
    } catch (e) {
      // Network failed, use stale cache if available
      if (cachedArtifact != null) {
        Log.d(
          'StacCloud: Using stale cache for ${artifactType.name} $artifactName due to network error',
        );
        return _buildArtifactCacheResponse(artifactType, cachedArtifact);
      }
      rethrow;
    }
  }

  /// Handles optimistic strategy: Return cache immediately, update in background.
  static Future<Response?> _handleArtifactOptimistic({
    required StacArtifactType artifactType,
    required String artifactName,
    StacCache? cachedArtifact,
    required bool isCacheValid,
    required StacCacheConfig config,
  }) async {
    // If cache exists (show stale cache while revalidating)
    if (cachedArtifact != null) {
      // Update in background if configured or cache is stale
      if (config.refreshInBackground || !isCacheValid) {
        _fetchAndUpdateArtifactInBackground(
          artifactType: artifactType,
          artifactName: artifactName,
          cachedVersion: cachedArtifact.version,
        );
      }
      return _buildArtifactCacheResponse(artifactType, cachedArtifact);
    }

    // No cache, must fetch from network
    return _fetchArtifactFromNetwork(
      artifactType: artifactType,
      artifactName: artifactName,
      saveToCache: true,
    );
  }

  /// Makes a network request to fetch artifact data.
  static Future<Response> _makeArtifactRequest({
    required StacArtifactType artifactType,
    required String artifactName,
  }) async {
    final fetchUrl = '${_getFetchUrl(artifactType)}/get-latest';
    final queryParamName = _getQueryParamName(artifactType);

    PackageInfo packageInfo = await PackageInfo.fromPlatform();

    var params = <String, dynamic>{
      queryParamName: artifactName,
      "appVersion": packageInfo.version,
    };
    print('\x1B[32m params $params fetch $fetchUrl \x1B[0m');

    return _dio.get(fetchUrl, queryParameters: params);
  }

  /// Fetches artifact data from network and optionally saves to cache.
  static Future<Response> _fetchArtifactFromNetwork({
    required StacArtifactType artifactType,
    required String artifactName,
    required bool saveToCache,
  }) async {
    final response = await _makeArtifactRequest(
      artifactType: artifactType,
      artifactName: artifactName,
    );

    print(
      '\x1B[32m fetchArtifactFromNetwork response.data ${response.data} \x1B[0m',
    );

    // Save to cache if enabled and response is valid
    final responseData = response.data;
    if (saveToCache && responseData is Map<String, dynamic>) {
      final results = responseData['result'];
      if (results is List && results.isNotEmpty && results.first is Map) {
        final result = Map<String, dynamic>.from(results.first as Map);
        final version = result['version']?.toString();
        final stacJson = result[_getJsonFieldName(artifactType)]?.toString();
        final name = result['name']?.toString();

        if (version != null && stacJson != null && name != null) {
          await StacCacheService.saveArtifact(
            name: name,
            stacJson: stacJson,
            version: version,
            artifactType: artifactType,
          );
        }
      }
    }

    return response;
  }

  /// Builds a Response from cached artifact data.
  static Response _buildArtifactCacheResponse(
    StacArtifactType artifactType,
    StacCache cachedArtifact,
  ) {
    final fetchUrl = _getFetchUrl(artifactType);
    return Response(
      requestOptions: RequestOptions(path: fetchUrl),
      data: {
        'result': [
          {
            'name': cachedArtifact.name,
            _getJsonFieldName(artifactType): cachedArtifact.stacJson,
            'version': cachedArtifact.version,
          },
        ],
      },
    );
  }

  /// Fetches the latest version in background and updates cache if newer.
  ///
  /// This method runs asynchronously without blocking the UI.
  /// If a newer version is found, it updates the cache for the next load.
  /// Prevents duplicate fetches for the same artifact.
  static Future<void> _fetchAndUpdateArtifactInBackground({
    required StacArtifactType artifactType,
    required String artifactName,
    required String cachedVersion,
  }) async {
    final inProgressSet = _backgroundFetchInProgress[artifactType]!;
    // Prevent duplicate background fetches for the same artifact
    if (!inProgressSet.add(artifactName)) return;

    try {
      final response = await _makeArtifactRequest(
        artifactType: artifactType,
        artifactName: artifactName,
      );

      final responseData = response.data;
      if (responseData is Map<String, dynamic>) {
        final results = responseData['result'];
        if (results is List && results.isNotEmpty && results.first is Map) {
          final result = Map<String, dynamic>.from(results.first as Map);
          final serverVersion = result['version']?.toString();
          final serverStacJson = result[_getJsonFieldName(artifactType)]
              ?.toString();
          final name = result['name']?.toString();

          // Only update if server has newer version
          if (serverVersion != null &&
              serverStacJson != null &&
              name != null &&
              _compareVersions(serverVersion, cachedVersion) > 0) {
            // Update cache with new version for next load
            await StacCacheService.saveArtifact(
              name: name,
              stacJson: serverStacJson,
              version: serverVersion,
              artifactType: artifactType,
            );
          }
        }
      }
    } catch (e) {
      // Silently fail - background update is optional
      Log.d(
        'StacCloud: Background update failed for ${artifactType.name} $artifactName: $e',
      );
    } finally {
      inProgressSet.remove(artifactName);
    }
  }

  /// Fetches a theme from Stac Cloud with intelligent caching.
  ///
  /// Uses the global cache configuration from [StacService.defaultCacheConfig],
  /// which is set via [Stac.initialize].
  static Future<Response?> fetchTheme({required String themeName}) async {
    return _fetchArtifact(
      artifactType: StacArtifactType.theme,
      artifactName: themeName,
    );
  }

  /// Clears the cache for a specific screen.
  static Future<bool> clearScreenCache(String routeName) {
    return StacCacheService.removeArtifact(routeName, StacArtifactType.screen);
  }

  /// Clears all cached screens.
  static Future<bool> clearAllCache() {
    return StacCacheService.clearAllArtifacts(StacArtifactType.screen);
  }

  /// Clears the cache for a specific theme.
  static Future<bool> clearThemeCache(String themeName) {
    return StacCacheService.removeArtifact(themeName, StacArtifactType.theme);
  }

  /// Clears all cached themes.
  static Future<bool> clearAllThemeCache() {
    return StacCacheService.clearAllArtifacts(StacArtifactType.theme);
  }
}
