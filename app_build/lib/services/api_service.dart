import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

// 🇨🇮 Change ça avec l'IP Tailscale de ton VPS
// 🇨🇮 IP publique du VPS (accessible partout, pas besoin de Tailscale)
// Pour utiliser Tailscale : remplacer par http://100.77.208.122:3000
const String BASE_URL = 'http://100.77.208.122:3000';

class ApiService {
  String? _token;

  String? get token => _token;

  void setToken(String t) => _token = t;

  // ==================== AUTH ====================

  Future<bool> setup(String masterPassword) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('$BASE_URL/api/setup'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'masterPassword': masterPassword}));
      final response = await request.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Setup error: $e');
      return false;
    }
  }

  Future<bool> login(String masterPassword) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('$BASE_URL/api/login'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'masterPassword': masterPassword}));
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        _token = data['token'];
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Login error: $e');
      return false;
    }
  }

  // ==================== PASSWORDS ====================

  Future<List<Map<String, dynamic>>> getPasswords() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('$BASE_URL/api/passwords'),
      );
      request.headers.add('Authorization', 'Bearer $_token');
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        return List<Map<String, dynamic>>.from(jsonDecode(body));
      }
      return [];
    } catch (e) {
      debugPrint('Get passwords error: $e');
      return [];
    }
  }

  Future<bool> addPassword({
    required String site,
    required String email,
    required String password,
    String? note,
  }) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('$BASE_URL/api/passwords'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'token': _token,
        'site': site,
        'email': email,
        'password': password,
        'note': note ?? '',
      }));
      final response = await request.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Add password error: $e');
      return false;
    }
  }

  Future<bool> deletePassword(int id) async {
    try {
      final client = HttpClient();
      final request = await client.deleteUrl(
        Uri.parse('$BASE_URL/api/passwords/$id'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'token': _token}));
      final response = await request.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Delete error: $e');
      return false;
    }
  }

  // ==================== MODIFIER ====================

  Future<bool> updatePassword({
    required int id,
    required String site,
    required String email,
    required String password,
    String? note,
  }) async {
    try {
      final client = HttpClient();
      final request = await client.putUrl(
        Uri.parse('$BASE_URL/api/passwords/$id'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'token': _token,
        'site': site,
        'email': email,
        'password': password,
        'note': note ?? '',
      }));
      final response = await request.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Update error: $e');
      return false;
    }
  }

  // ==================== GENERATEUR ====================

  Future<String> generatePassword({int length = 20}) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('$BASE_URL/api/generate?length=$length'),
      );
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        return data['password'];
      }
      return '';
    } catch (e) {
      debugPrint('Generate error: $e');
      return '';
    }
  }

  // ==================== EXPORT JSON ====================

  Future<List<Map<String, dynamic>>> exportPasswords() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('$BASE_URL/api/export'),
      );
      request.headers.add('Authorization', 'Bearer $_token');
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        return List<Map<String, dynamic>>.from(jsonDecode(body));
      }
      return [];
    } catch (e) {
      debugPrint('Export error: $e');
      return [];
    }
  }

  // ==================== EXPORT CSV ====================

  Future<String> exportCsv() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('$BASE_URL/api/export/csv'),
      );
      request.headers.add('Authorization', 'Bearer $_token');
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        return data['csv'] ?? '';
      }
      return '';
    } catch (e) {
      debugPrint('Export CSV error: $e');
      return '';
    }
  }

  // ==================== IMPORT JSON ====================

  Future<int> importPasswords(List<Map<String, dynamic>> passwords) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('$BASE_URL/api/import'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'token': _token,
        'passwords': passwords,
      }));
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        return data['imported'] ?? 0;
      }
      return 0;
    } catch (e) {
      debugPrint('Import error: $e');
      return 0;
    }
  }

  // ==================== IMPORT CSV ====================

  Future<Map<String, dynamic>> importCsv(String csvContent) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('$BASE_URL/api/import/csv'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'token': _token,
        'csv': csvContent,
      }));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body);
    } catch (e) {
      debugPrint('Import CSV error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}
