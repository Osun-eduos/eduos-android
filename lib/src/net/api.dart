// Talks to eduos-api (sign-in) and eduos-sync (snapshot and uploads).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../store/vault.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message, {this.code});
  final int status;
  final String message;
  final String? code;
  bool get offline => status == 0;
  @override
  String toString() => message;
}

class Servers {
  Servers({required this.api, required this.sync});
  final String api;
  final String sync;
}

/// Signed-in user as returned by eduos-api.
class SignedIn {
  SignedIn({required this.fullName, required this.role, required this.mustChangePassword, this.lga});
  final String fullName;
  final String role;
  final bool mustChangePassword;
  /// The LGA an LGA officer or inspector covers; null for state-wide.
  final String? lga;
}

/// The password was right and the account uses two-step sign-in: answer [mfaToken] with a code.
class CodeNeeded implements Exception {
  CodeNeeded(this.mfaToken);
  final String mfaToken;
}

class Api {
  Api({required this.client, required this.vault, required this.servers});
  final http.Client client;
  final Vault vault;
  Servers servers;
  static const timeout = Duration(seconds: 30);

  Future<String?> get accessToken => vault.read('accessToken');

  Future<Map<String, dynamic>> _send(String method, Uri url, {Map<String, String>? headers, Object? body}) async {
    final req = http.Request(method, url)
      ..headers.addAll({'Content-Type': 'application/json', 'Accept': 'application/json', ...?headers});
    if (body != null) req.body = jsonEncode(body);
    return _sendRequest(req);
  }

  Future<Map<String, dynamic>> _sendRequest(http.BaseRequest req, {Duration timeout = timeout}) async {
    http.Response res;
    try {
      res = await http.Response.fromStream(await client.send(req).timeout(timeout)).timeout(timeout);
    } on TimeoutException {
      throw ApiException(0, 'No connection. Your changes are saved on this phone.');
    } on SocketException {
      throw ApiException(0, 'No connection. Your changes are saved on this phone.');
    } on HandshakeException {
      throw ApiException(0, 'Could not make a secure connection to the EduOS service.');
    } on http.ClientException {
      throw ApiException(0, 'No connection. Your changes are saved on this phone.');
    }
    Map<String, dynamic> json = {};
    if (res.body.isNotEmpty) {
      try {
        final d = jsonDecode(res.body);
        if (d is Map<String, dynamic>) json = d;
        if (d is List) json = {'items': d};
      } catch (_) {}
    }
    if (res.statusCode >= 400) {
      var msg = json['message'];
      if (msg is List && msg.isNotEmpty) msg = msg.first;
      throw ApiException(res.statusCode, msg is String ? msg : _fallback(res.statusCode), code: json['code'] as String?);
    }
    return json;
  }

  String _fallback(int status) => switch (status) {
        401 => 'Please sign in again.',
        429 => 'Too many attempts. Wait a minute and try again.',
        >= 500 => 'The EduOS service is having trouble. Try again shortly.',
        _ => 'Something went wrong ($status).',
      };

  Future<void> _keep(Map<String, dynamic> r) async {
    await vault.write('accessToken', r['accessToken'] as String);
    if (r['refreshToken'] is String) await vault.write('refreshToken', r['refreshToken'] as String);
  }

  SignedIn _user(Map<String, dynamic> r) {
    final u = r['user'] as Map<String, dynamic>;
    return SignedIn(fullName: u['fullName'], role: u['role'], mustChangePassword: u['mustChangePassword'] == true, lga: u['lga'] as String?);
  }

  /// Signs in with a password. Throws [CodeNeeded] when the account also needs an authenticator code.
  Future<SignedIn> login(String identifier, String password) async {
    final r = await _send('POST', Uri.parse('${servers.api}/auth/login'),
        headers: {'X-Client': 'mobile'}, body: {'identifier': identifier.trim(), 'password': password});
    if (r['mfaRequired'] == true) throw CodeNeeded(r['mfaToken'] as String);
    await _keep(r);
    return _user(r);
  }

  /// Second step of two-step sign-in: a 6-digit authenticator code or a recovery code.
  Future<SignedIn> loginWithCode(String mfaToken, String code) async {
    final r = await _send('POST', Uri.parse('${servers.api}/auth/login/code'),
        headers: {'X-Client': 'mobile'}, body: {'mfaToken': mfaToken, 'code': code.trim()});
    await _keep(r);
    return _user(r);
  }

  Future<SignedIn> changePassword(String current, String next) async {
    final r = await _send('POST', Uri.parse('${servers.api}/auth/change-password'),
        headers: {'X-Client': 'mobile', 'Authorization': 'Bearer ${await accessToken}'}, body: {'currentPassword': current, 'newPassword': next});
    await _keep(r);
    return _user(r);
  }

  /// Swaps the refresh token for new tokens. Returns false if the teacher must sign in again.
  Future<bool> refresh() async {
    final rt = await vault.read('refreshToken');
    if (rt == null) return false;
    try {
      await _keep(await _send('POST', Uri.parse('${servers.api}/auth/refresh'), headers: {'X-Client': 'mobile'}, body: {'refreshToken': rt}));
      return true;
    } on ApiException catch (e) {
      if (e.status == 401) return false;
      rethrow;
    }
  }

  Future<void> logout() async {
    final rt = await vault.read('refreshToken');
    if (rt != null) {
      try {
        await _send('POST', Uri.parse('${servers.api}/auth/logout'), headers: {'X-Client': 'mobile'}, body: {'refreshToken': rt});
      } catch (_) {}
    }
    await vault.delete('accessToken');
    await vault.delete('refreshToken');
  }

  Future<Map<String, dynamic>> snapshot() async =>
      _send('GET', Uri.parse('${servers.sync}/v1/snapshot'), headers: {'Authorization': 'Bearer ${await accessToken}'});

  Future<List<Map<String, dynamic>>> push(String device, List<Map<String, dynamic>> events) async {
    final r = await _send('POST', Uri.parse('${servers.sync}/v1/sync'),
        headers: {'Authorization': 'Bearer ${await accessToken}', 'X-Device-Id': device}, body: {'events': events});
    return (r['results'] as List).cast<Map<String, dynamic>>();
  }

  // ---- Calls straight to eduos-api (inspectors) ----

  Future<Map<String, String>> _auth() async => {'Authorization': 'Bearer ${await accessToken}'};

  /// GET from eduos-api. A list response comes back as {'items': [...]}.
  Future<Map<String, dynamic>> apiGet(String path) async => _send('GET', Uri.parse('${servers.api}$path'), headers: await _auth());

  Future<Map<String, dynamic>> apiPost(String path, Object body) async => _send('POST', Uri.parse('${servers.api}$path'), headers: await _auth(), body: body);

  Future<Map<String, dynamic>> apiDelete(String path) async => _send('DELETE', Uri.parse('${servers.api}$path'), headers: await _auth());

  /// Uploads a photo file as multipart form data with the given fields.
  Future<Map<String, dynamic>> apiUpload(String path, File file, Map<String, String> fields) async {
    final req = http.MultipartRequest('POST', Uri.parse('${servers.api}$path'))
      ..headers.addAll({'Accept': 'application/json', ...await _auth()})
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes('photo', await file.readAsBytes(), filename: file.uri.pathSegments.last));
    // Photos are larger than other requests, so allow longer on a slow connection.
    return _sendRequest(req, timeout: const Duration(seconds: 120));
  }
}
