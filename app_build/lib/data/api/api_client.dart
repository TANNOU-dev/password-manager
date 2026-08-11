import 'dart:convert';

import 'package:http/http.dart' as http;

/// Transport HTTP. On passe par `package:http` et non par `HttpClient` de
/// `dart:io` : ce dernier n'existe pas sur le web, ce qui empêchait l'app d'y
/// tourner du tout.
///
/// Surchargeable au build :
///   flutter run --dart-define=PASSVAULT_API_URL=https://coffre.exemple.com
const String kDefaultApiUrl = String.fromEnvironment(
  'PASSVAULT_API_URL',
  defaultValue: 'http://localhost:3000',
);

/// Vrai si le trafic quitte la machine sans TLS.
///
/// Une boucle locale en HTTP ne pose pas de problème — le trafic ne sort pas de
/// l'appareil — alors qu'un HTTP vers une IP distante expose les métadonnées :
/// à qui on parle, quand, et à quelle fréquence. Seul le second cas mérite un
/// avertissement, sinon on crie au loup en développement.
bool isInsecureServerUrl(String url) {
  if (!url.startsWith('http://')) return false;
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  const loopback = {'localhost', '127.0.0.1', '::1', '0.0.0.0'};
  return !loopback.contains(host);
}

sealed class ApiFailure implements Exception {
  final String message;
  const ApiFailure(this.message);
  @override
  String toString() => '$runtimeType: $message';
}

/// Le serveur est injoignable : pas de réseau, mauvaise URL, TLS refusé.
/// À distinguer d'un refus applicatif, parce que l'app peut alors basculer sur
/// son cache local au lieu d'afficher une erreur.
class NetworkFailure extends ApiFailure {
  const NetworkFailure(super.message);
}

/// La session n'est plus valable. Impose un reverrouillage.
class UnauthorizedFailure extends ApiFailure {
  const UnauthorizedFailure(super.message);
}

class RateLimitedFailure extends ApiFailure {
  final int retryAfterSeconds;
  const RateLimitedFailure(super.message, this.retryAfterSeconds);
}

class ConflictFailure extends ApiFailure {
  const ConflictFailure(super.message);
}

class ServerFailure extends ApiFailure {
  final int statusCode;
  const ServerFailure(this.statusCode, super.message);
}

class ApiClient {
  ApiClient({String? baseUrl, http.Client? httpClient})
      : baseUrl = _normalize(baseUrl ?? kDefaultApiUrl),
        _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  static String _normalize(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// Le serveur ne renvoie jamais de secret déchiffrable, mais il renvoie des
  /// blobs : on refuse quand même toute réponse mise en cache.
  Map<String, String> _headers(String? token, {bool hasBody = false}) => {
        if (hasBody) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path, {String? token}) =>
      _send('GET', path, token: token);

  Future<dynamic> post(String path, {Object? body, String? token}) =>
      _send('POST', path, body: body, token: token);

  Future<dynamic> put(String path, {Object? body, String? token}) =>
      _send('PUT', path, body: body, token: token);

  Future<dynamic> delete(String path, {Object? body, String? token}) =>
      _send('DELETE', path, body: body, token: token);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final request = http.Request(method, uri)
      ..headers.addAll(_headers(token, hasBody: body != null));
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } catch (e) {
      throw NetworkFailure('Serveur injoignable ($uri) : $e');
    }

    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    dynamic parsed;
    if (response.body.isNotEmpty) {
      try {
        parsed = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        // Un corps illisible sur un code d'erreur n'est pas surprenant
        // (page HTML d'un proxy, par exemple) : on garde le code.
        parsed = null;
      }
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) return parsed;

    final message = (parsed is Map && parsed['error'] is String)
        ? parsed['error'] as String
        : 'Réponse HTTP $status';

    throw switch (status) {
      401 => UnauthorizedFailure(message),
      409 => ConflictFailure(message),
      429 => RateLimitedFailure(
          message,
          (parsed is Map ? parsed['retryAfterSeconds'] as int? : null) ?? 60,
        ),
      _ => ServerFailure(status, message),
    };
  }

  void close() => _http.close();
}
