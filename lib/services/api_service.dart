import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'auth_service.dart';
import '../models/photo.dart';
import '../config/env.dart';

class ApiService {
  // URL definie dans le fichier .env (API_BASE_URL)
  final String baseUrl = "${Env.apiBaseUrl}/photos";
  final AuthService authService = AuthService();

  // Types MIME acceptes par le backend, par extension de fichier
  static const Map<String, String> _imageMimeTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
  };

  // Authenticated request with JWT (auto refresh on 401, see AuthService.sendAuthorized)
  Future<http.Response> _authorized(
    Future<http.Response> Function(Map<String, String> headers) send, {
    bool json = true,
    Duration timeout = AuthService.defaultTimeout,
  }) async {
    final response = await authService.sendAuthorized(send, json: json, timeout: timeout);
    _handleResponse(response);
    return response;
  }

  // Handle response and check for auth errors
  void _handleResponse(http.Response response) {
    if (response.statusCode == 401) {
      throw Exception('Unauthorized - Please login again');
    }
    if (response.statusCode == 403) {
      throw Exception('Forbidden - Invalid token');
    }
    if (response.statusCode >= 500) {
      throw Exception('Server error - Please try again later');
    }
  }

  // Read the error message sent by the backend: { success: false, message }
  String _errorMessage(http.Response response, String fallback) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic> && data['message'] is String) {
        return data['message'] as String;
      }
    } catch (_) {
      // Body is not JSON: keep the fallback message
    }
    return fallback;
  }

  // Get all photos of the logged in user (GET /photos)
  Future<List<Photo>> getPhotos() async {
    final response = await _authorized(
      (headers) => http.get(Uri.parse(baseUrl), headers: headers),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Photo.fromJson(json)).toList();
    }
    throw Exception(_errorMessage(response, 'Failed to load photos'));
  }

  // Get a single photo by ID (GET /photos/:id)
  Future<Photo> getPhoto(int id) async {
    final response = await _authorized(
      (headers) => http.get(Uri.parse("$baseUrl/$id"), headers: headers),
    );

    if (response.statusCode == 200) {
      return Photo.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 404) {
      throw Exception('Photo not found');
    }
    throw Exception(_errorMessage(response, 'Failed to load photo'));
  }

  // Upload a photo (POST /photos, multipart/form-data, field "photo")
  Future<Photo> uploadPhoto(XFile image) async {
    // Mobile : le nom vient du chemin du fichier ; web : du nom d'origine
    final fileName = image.name.isNotEmpty
        ? image.name
        : image.path.split(RegExp(r'[/\\]')).last;
    final extension = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    final mimeType = _imageMimeTypes[extension] ?? image.mimeType;
    if (mimeType == null || !_imageMimeTypes.containsValue(mimeType)) {
      throw Exception('Unsupported image format (JPEG, PNG, WEBP or GIF)');
    }

    final bytes = await image.readAsBytes();

    final response = await _authorized(
      (headers) async {
        // Nouvelle requete a chaque tentative : une MultipartRequest ne s'envoie qu'une fois
        final request = http.MultipartRequest('POST', Uri.parse(baseUrl))
          ..headers.addAll(headers)
          ..files.add(http.MultipartFile.fromBytes(
            'photo',
            bytes,
            filename: fileName,
            contentType: MediaType.parse(mimeType),
          ));
        return http.Response.fromStream(await request.send());
      },
      json: false,
      timeout: const Duration(seconds: 60),
    );

    if (response.statusCode == 201) {
      return Photo.fromJson(jsonDecode(response.body));
    }
    throw Exception(_errorMessage(response, 'Failed to upload photo'));
  }

  // Delete a photo (DELETE /photos/:id)
  Future<void> deletePhoto(int id) async {
    final response = await _authorized(
      (headers) => http.delete(Uri.parse("$baseUrl/$id"), headers: headers),
    );

    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Failed to delete photo'));
    }
  }
}
