import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:photo_app/services/api_service.dart';
import 'package:photo_app/services/auth_service.dart';

/// Test de bout en bout des services Flutter contre le VRAI backend.
/// Ignore par defaut. Pour le lancer (backend demarre) :
///   flutter test test/api_e2e_test.dart --dart-define=E2E_API=http://localhost:3000/api
const e2eApi = String.fromEnvironment('E2E_API');

// PNG 1x1 pixel
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tempDir;

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=$e2eApi');
    tempDir = Directory.systemTemp.createTempSync('photo_e2e_');
  });
  tearDownAll(() => tempDir.deleteSync(recursive: true));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Fichier sur disque, comme ceux renvoyes par image_picker sur Android / iOS
  XFile fileOnDisk(String name) {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name')..writeAsBytesSync(png);
    return XFile(file.path);
  }

  test('every backend endpoint is consumed by the mobile services', () async {
    final auth = AuthService();
    final api = ApiService();
    final email = 'e2e_${DateTime.now().millisecondsSinceEpoch}@example.com';

    // POST /auth/register
    expect(await auth.register('E2E Mobile', email, 'secret123'), isTrue);
    expect(await auth.getToken(), isNotNull);
    expect(await auth.getRefreshToken(), isNotNull);

    // POST /auth/login
    expect(await auth.login(email, 'secret123'), isTrue);

    // GET /auth/me
    final profile = await auth.getProfile();
    expect(profile?['email'], email);
    expect(profile?['name'], 'E2E Mobile');

    // GET /photos (vide)
    expect(await api.getPhotos(), isEmpty);

    // POST /photos (multipart)
    final uploaded = await api.uploadPhoto(fileOnDisk('pixel.png'));
    expect(uploaded.url, contains('/uploads/photo_'));
    expect(uploaded.mimeType, 'image/png');
    expect(uploaded.originalName, 'pixel.png');
    expect(uploaded.size, png.length);

    // GET /uploads/<fichier> (ce que charge Image.network)
    final file = await http.get(Uri.parse(uploaded.url));
    expect(file.statusCode, 200);
    expect(file.bodyBytes, png);

    // GET /photos/:id
    expect((await api.getPhoto(uploaded.id)).id, uploaded.id);

    // GET /photos
    expect((await api.getPhotos()).map((p) => p.id), [uploaded.id]);

    // POST /auth/refresh : access token invalide -> refresh automatique puis requete rejouee
    final refreshBefore = await auth.getRefreshToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', 'invalid-access-token');
    expect((await api.getPhotos()).length, 1);
    expect(await auth.getToken(), isNot('invalid-access-token'));
    expect(await auth.getRefreshToken(), isNot(refreshBefore));

    // Format refuse cote client avant tout appel reseau
    await expectLater(
      api.uploadPhoto(fileOnDisk('document.pdf')),
      throwsA(predicate((e) => e.toString().contains('Unsupported image format'))),
    );

    // DELETE /photos/:id
    await api.deletePhoto(uploaded.id);
    expect(await api.getPhotos(), isEmpty);
    await expectLater(
      api.getPhoto(uploaded.id),
      throwsA(predicate((e) => e.toString().contains('Photo not found'))),
    );

    // POST /auth/logout : la session est revoquee cote serveur
    final refreshBeforeLogout = await auth.getRefreshToken();
    await auth.logout();
    expect(await auth.getToken(), isNull);
    expect(await auth.getRefreshToken(), isNull);

    final reuse = await http.post(
      Uri.parse('$e2eApi/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshBeforeLogout}),
    );
    expect(reuse.statusCode, 401);
  }, skip: e2eApi.isEmpty ? 'Run with --dart-define=E2E_API=http://localhost:3000/api' : false);
}
