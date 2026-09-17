import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';

class AuthService {
  // URL definie dans le fichier .env (API_BASE_URL)
  final String baseUrl = Env.apiBaseUrl;

  static const String _tokenKey = 'jwt_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const Duration defaultTimeout = Duration(seconds: 15);

  // Refresh en cours, partage par toutes les instances : si plusieurs requetes
  // recoivent 401 en meme temps, un seul POST /auth/refresh est envoye
  // (le refresh token est a usage unique cote serveur : rotation).
  static Future<bool>? _pendingRefresh;

  /// Execute une requete HTTP avec un timeout et traduit les erreurs reseau
  /// (serveur eteint, mauvaise IP, pas de connexion) en message lisible.
  static Future<T> withNetworkErrors<T>(
    Future<T> Function() request, {
    Duration timeout = defaultTimeout,
  }) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw Exception('Server timeout - Please try again later');
    } on http.ClientException {
      throw Exception('Server unreachable - Check your connection');
    }
  }

  // Decode a JSON response body ({} if the body is not a JSON object)
  Map<String, dynamic> _decode(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) return data;
    } catch (_) {
      // Body is not JSON
    }
    return {};
  }

  Future<http.Response> _postJson(String path, Map<String, dynamic> body) {
    return withNetworkErrors(() => http.post(
          Uri.parse("$baseUrl$path"),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ));
  }

  // Register a new user (POST /auth/register)
  Future<bool> register(String name, String email, String password) async {
    final response = await _postJson('/auth/register', {
      'name': name,
      'email': email,
      'password': password,
    });

    final data = _decode(response);
    if (response.statusCode == 201) {
      await _saveTokens(data['token'], data['refreshToken']);
      return true;
    }
    throw Exception(data['message'] ?? 'Registration failed');
  }

  // Login user (POST /auth/login)
  Future<bool> login(String email, String password) async {
    final response = await _postJson('/auth/login', {
      'email': email,
      'password': password,
    });

    final data = _decode(response);
    if (response.statusCode == 200) {
      await _saveTokens(data['token'], data['refreshToken']);
      return true;
    }
    throw Exception(data['message'] ?? 'Login failed');
  }

  // Get current user profile (GET /auth/me)
  Future<Map<String, dynamic>?> getProfile() async {
    if (await getToken() == null) return null;

    try {
      final response = await sendAuthorized(
        (headers) => http.get(Uri.parse("$baseUrl/auth/me"), headers: headers),
      );
      return response.statusCode == 200 ? _decode(response) : null;
    } catch (e) {
      return null;
    }
  }

  /// Envoie une requete authentifiee (header Bearer). Si l'access token a expire (401),
  /// la session est renouvelee via POST /auth/refresh puis la requete est rejouee une fois.
  Future<http.Response> sendAuthorized(
    Future<http.Response> Function(Map<String, String> headers) send, {
    bool json = true,
    Duration timeout = defaultTimeout,
  }) async {
    Future<http.Response> attempt(String? token) => withNetworkErrors(
          () => send({
            // Pas de Content-Type pour le multipart : http ajoute lui-meme le boundary
            if (json) 'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          }),
          timeout: timeout,
        );

    final token = await getToken();
    var response = await attempt(token);

    if (response.statusCode == 401) {
      // Session deja renouvelee par une requete parallele ? Sinon POST /auth/refresh
      final current = await getToken();
      final renewed = (current != null && current != token) || await refreshSession();
      if (renewed) response = await attempt(await getToken());
    }
    return response;
  }

  /// Renouvelle la session (POST /auth/refresh) : nouveau couple access + refresh token.
  /// Renvoie false si le refresh token est absent, expire ou revoque.
  Future<bool> refreshSession() {
    return _pendingRefresh ??= _refresh().whenComplete(() => _pendingRefresh = null);
  }

  Future<bool> _refresh() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) return false;

    try {
      final response = await _postJson('/auth/refresh', {'refreshToken': refreshToken});
      if (response.statusCode == 200) {
        final data = _decode(response);
        await _saveTokens(data['token'], data['refreshToken']);
        return true;
      }
      // Refresh token invalide, expire ou revoque : la session est terminee
      if (response.statusCode == 400 || response.statusCode == 401) {
        await _clearTokens();
      }
      return false;
    } catch (_) {
      // Serveur injoignable : on garde les tokens pour reessayer plus tard
      return false;
    }
  }

  // Logout user (POST /auth/logout) : revoque la session cote serveur,
  // puis efface les tokens locaux meme si le serveur est injoignable.
  Future<void> logout() async {
    if (await getToken() != null) {
      try {
        await sendAuthorized((headers) async => http.post(
              Uri.parse("$baseUrl/auth/logout"),
              headers: headers,
              body: jsonEncode({'refreshToken': await getRefreshToken()}),
            ));
      } catch (_) {
        // Serveur injoignable : deconnexion locale uniquement
      }
    }
    await _clearTokens();
  }

  // Save JWT tokens to local storage
  Future<void> _saveTokens(String token, String? refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    if (refreshToken != null) {
      await prefs.setString(_refreshTokenKey, refreshToken);
    }
  }

  Future<void> _clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
  }

  // Get JWT access token from local storage
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  // Get refresh token from local storage
  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }
}
