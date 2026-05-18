import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';

class AuthService {
  final _storage = const FlutterSecureStorage();
  static const _jwtKey = 'jwt';
  static const _refreshTokenKey = 'refresh_token';
  static const _memberIdKey = 'member_id';
  static const _pseudoKey = 'pseudo';
  static const _emailKey = 'email';
  static DateTime? _lastRefreshAttempt;

  Future<bool> isTokenValid() async {
    final jwt = await _storage.read(key: _jwtKey);
    if (jwt == null || jwt.isEmpty) {
      return false;
    }

    try {
      final decodedToken = JwtDecoder.decode(jwt);
      final expiration = decodedToken['exp'] as int?;
      if (expiration != null) {
        final expirationDate = DateTime.fromMillisecondsSinceEpoch(expiration * 1000);
        if (expirationDate.isBefore(DateTime.now())) {
          final refreshed = await refreshToken(maxRetries: 1);
          return refreshed;
        }
      }
    } catch (e) {
      return false;
    }

    try {
      final url = Uri.parse('https://www.1clic1don.fr/app/verify_token.php');
      final response = await http
          .get(
        url,
        headers: {'Authorization': 'Bearer $jwt'},
      )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          return false;
        }
        final data = jsonDecode(response.body);
        final memberId = data['member_id']?.toString();
        final pseudo = data['pseudo']?.toString();
        final email = data['email']?.toString();
        if (memberId != null) {
          await _storage.write(key: _memberIdKey, value: memberId);
        }
        if (pseudo != null) {
          await _storage.write(key: _pseudoKey, value: pseudo);
        }
        if (email != null) {
          await _storage.write(key: _emailKey, value: email);
        }
        return true;
      } else {
        if (response.statusCode == 500) {
          final refreshed = await refreshToken(maxRetries: 1);
          return refreshed;
        }
        if (response.body.isNotEmpty) {
          try {
            // Supprimé : final data = jsonDecode(response.body);
            // Supprimé : final error = data['error'] ?? 'Unknown error';
          } catch (e) {
            return false;
          }
        }
        return false;
      }
    } catch (e) {
      if (e is FormatException) {
        final refreshed = await refreshToken(maxRetries: 1);
        return refreshed;
      }
      return false;
    }
  }

  Future<bool> refreshToken({int maxRetries = 1}) async {
    if (maxRetries <= 0) {
      return false;
    }

    // Éviter les rafraîchissements trop fréquents
    if (_lastRefreshAttempt != null &&
        DateTime.now().difference(_lastRefreshAttempt!).inSeconds < 10) {
      return false;
    }
    _lastRefreshAttempt = DateTime.now();

    final refreshTokenString = await _storage.read(key: _refreshTokenKey);
    if (refreshTokenString == null || refreshTokenString.isEmpty) {
      return false;
    }

    try {
      final url = Uri.parse('https://www.1clic1don.fr/app/refresh_token.php');
      final response = await http
          .post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshTokenString}),
      )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          return false;
        }
        final data = jsonDecode(response.body);
        if (data['jwt'] == null) {
          return false;
        }
        await _storage.write(key: _jwtKey, value: data['jwt']);
        if (data['refresh_token'] != null) {
          await _storage.write(key: _refreshTokenKey, value: data['refresh_token']);
        }
        if (data['member_id'] != null) {
          await _storage.write(key: _memberIdKey, value: data['member_id'].toString());
        }
        if (data['pseudo'] != null) {
          await _storage.write(key: _pseudoKey, value: data['pseudo']);
        }
        if (data['email'] != null) {
          await _storage.write(key: _emailKey, value: data['email']);
        }
        return true;
      } else {
        if (response.statusCode == 500) {
          await Future.delayed(const Duration(seconds: 2));
          return await refreshToken(maxRetries: maxRetries - 1);
        }
        if (response.body.isNotEmpty) {
          // Supprimé : try { final data = jsonDecode(response.body); final error = data['error'] ?? 'Unknown error'; } catch (e) { return false; }
        }
        return false;
      }
    } catch (e) {
      if (e is FormatException) {
        await Future.delayed(const Duration(seconds: 2));
        return await refreshToken(maxRetries: maxRetries - 1);
      }
      return false;
    }
  }

  Future<void> saveAuthData({
    required String jwt,
    required String refreshToken,
    required String memberId,
    required String pseudo,
    String? email,
  }) async {
    await _storage.write(key: _jwtKey, value: jwt);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    await _storage.write(key: _memberIdKey, value: memberId);
    await _storage.write(key: _pseudoKey, value: pseudo);
    if (email != null) {
      await _storage.write(key: _emailKey, value: email);
    }
  }

  Future<String?> getMemberId() async {
    return await _storage.read(key: _memberIdKey);
  }

  Future<String?> getPseudo() async {
    // Vérifier si l'utilisateur est authentifié
    final isValid = await isTokenValid();
    if (!isValid) {
      return null;
    }
    // Sinon, lire le pseudo stocké
    return await _storage.read(key: _pseudoKey);
  }

  Future<String?> getEmail() async {
    return await _storage.read(key: _emailKey);
  }

  Future<String?> getJwt() async {
    final jwt = await _storage.read(key: _jwtKey);
    return jwt;
  }

  Future<void> logout() async {
    await _storage.deleteAll();
  }

  Future<Map<String, dynamic>> updateProfile({
    String? pseudo,
    String? email,
    String? password,
    bool? newsletter,
    bool? rappelDon,
  }) async {
    final jwt = await getJwt();
    if (jwt == null || jwt.isEmpty) {
      await logout();
      return {
        'success': false,
        'message': 'auth_error',
      };
    }

    final body = <String, dynamic>{};
    if (pseudo != null && pseudo.trim().isNotEmpty) body['pseudo'] = pseudo.trim();
    if (email != null && email.trim().isNotEmpty) body['email'] = email.trim();
    if (password != null && password.isNotEmpty) body['password'] = password;
    if (newsletter != null) body['newsletter'] = newsletter;
    if (rappelDon != null) body['rappel_don'] = rappelDon;

    if (body.isEmpty) {
      return {
        'success': false,
        'message': 'profile_no_changes',
      };
    }

    try {
      final url = Uri.parse('https://www.1clic1don.fr/app/update_profile.php');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        // Optionnel : mise à jour stockage local
        if (data['pseudo'] != null) {
          await _storage.write(key: _pseudoKey, value: data['pseudo']);
        }
        if (data['email'] != null) {
          await _storage.write(key: _emailKey, value: data['email']);
        }

        return {
          'success': true,
          'message': data['message'] ?? 'profile_success_update',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'profile_error_update',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'server_error',
      };
    }
  }
}