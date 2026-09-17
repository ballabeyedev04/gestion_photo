import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:photo_app/screens/home_page.dart';

/// Ecran d'accueil branche sur un faux backend (MockClient) :
/// verifie que chaque action de l'UI appelle le bon endpoint de l'API.
void main() {
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://api.test/api'));

  Map<String, dynamic> photoJson(int id) => {
        'id': id,
        'url': 'http://api.test/uploads/photo_$id.jpg',
        'original_name': 'photo_$id.jpg',
        'mime_type': 'image/jpeg',
        'size': 2048,
        'created_at': '2026-09-10T10:00:00.000Z',
      };

  http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  final profile = {'id': 1, 'name': 'Awa', 'email': 'awa@test.com'};

  testWidgets('loads profile + photos, then deletes a photo', (tester) async {
    SharedPreferences.setMockInitialValues({'jwt_token': 'access-1', 'refresh_token': 'refresh-1'});
    final photos = [photoJson(1), photoJson(2)];
    final calls = <String>[];
    final authHeaders = <String?>{};

    final client = MockClient((request) async {
      final call = '${request.method} ${request.url.path}';
      calls.add(call);
      authHeaders.add(request.headers['Authorization']);
      switch (call) {
        case 'GET /api/auth/me':
          return jsonResponse(profile);
        case 'GET /api/photos':
          return jsonResponse(photos);
        case 'DELETE /api/photos/1':
          photos.removeWhere((p) => p['id'] == 1);
          return jsonResponse({'message': 'Photo deleted successfully'});
      }
      return jsonResponse({'success': false, 'message': 'Route not found'}, 404);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();

      expect(calls, containsAll(['GET /api/auth/me', 'GET /api/photos']));
      expect(find.text('Awa • 2 photos'), findsOneWidget);

      // Bouton supprimer de la 1re photo -> confirmation -> DELETE
      await tester.tap(find.byTooltip('Supprimer').first);
      await tester.pumpAndSettle();
      expect(find.text('Supprimer la photo'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
      await tester.pumpAndSettle();
    }, () => client);

    expect(calls, contains('DELETE /api/photos/1'));
    expect(find.text('Awa • 1 photo'), findsOneWidget);
    expect(find.text('Photo supprimée avec succès'), findsOneWidget);
    expect(authHeaders, {'Bearer access-1'});
  });

  testWidgets('expired token: refreshes the session once and retries', (tester) async {
    SharedPreferences.setMockInitialValues({'jwt_token': 'expired', 'refresh_token': 'refresh-1'});
    final calls = <String>[];
    String? refreshBody;

    final client = MockClient((request) async {
      final call = '${request.method} ${request.url.path}';
      calls.add(call);
      if (call == 'POST /api/auth/refresh') {
        refreshBody = request.body;
        return jsonResponse({'token': 'access-2', 'refreshToken': 'refresh-2'});
      }
      if (request.headers['Authorization'] != 'Bearer access-2') {
        return jsonResponse({'success': false, 'message': 'Token expired'}, 401);
      }
      if (call == 'GET /api/auth/me') return jsonResponse(profile);
      if (call == 'GET /api/photos') return jsonResponse([photoJson(1)]);
      return jsonResponse({'success': false, 'message': 'Route not found'}, 404);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
    }, () => client);

    // /me et /photos recoivent 401 en parallele -> un seul refresh (rotation du refresh token)
    expect(calls.where((c) => c == 'POST /api/auth/refresh').length, 1);
    expect(jsonDecode(refreshBody!), {'refreshToken': 'refresh-1'});
    expect(find.text('Awa • 1 photo'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('jwt_token'), 'access-2');
    expect(prefs.getString('refresh_token'), 'refresh-2');
  });

  testWidgets('refresh refused: clears the session and goes back to login', (tester) async {
    SharedPreferences.setMockInitialValues({'jwt_token': 'expired', 'refresh_token': 'revoked'});
    final calls = <String>[];

    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      return jsonResponse({'success': false, 'message': 'Token expired'}, 401);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
    }, () => client);

    expect(calls, contains('POST /api/auth/refresh'));
    expect(find.text('Connexion'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('jwt_token'), isNull);
    expect(prefs.getString('refresh_token'), isNull);
  });

  testWidgets('opening a photo calls GET /photos/:id (deleted photo -> list reloaded)', (tester) async {
    SharedPreferences.setMockInitialValues({'jwt_token': 'access-1', 'refresh_token': 'refresh-1'});
    final calls = <String>[];
    var photos = [photoJson(1)];

    final client = MockClient((request) async {
      final call = '${request.method} ${request.url.path}';
      calls.add(call);
      switch (call) {
        case 'GET /api/auth/me':
          return jsonResponse(profile);
        case 'GET /api/photos':
          return jsonResponse(photos);
        case 'GET /api/photos/1':
          // Photo supprimee entre-temps (ex: depuis un autre appareil)
          photos = [];
          return jsonResponse({'success': false, 'message': 'Photo not found'}, 404);
      }
      return jsonResponse({'success': false, 'message': 'Route not found'}, 404);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Hero).first, warnIfMissed: false);
      await tester.pumpAndSettle();
    }, () => client);

    expect(calls, contains('GET /api/photos/1'));
    expect(find.text('Cette photo n\'existe plus'), findsOneWidget);
    expect(calls.where((c) => c == 'GET /api/photos').length, 2);
    expect(find.text('Aucune photo'), findsOneWidget);
  });

  testWidgets('logout revokes the session on the server (POST /auth/logout)', (tester) async {
    SharedPreferences.setMockInitialValues({'jwt_token': 'access-1', 'refresh_token': 'refresh-1'});
    final calls = <String>[];
    String? logoutBody;

    final client = MockClient((request) async {
      final call = '${request.method} ${request.url.path}';
      calls.add(call);
      switch (call) {
        case 'GET /api/auth/me':
          return jsonResponse(profile);
        case 'GET /api/photos':
          return jsonResponse([]);
        case 'POST /api/auth/logout':
          logoutBody = request.body;
          return jsonResponse({'message': 'Logged out successfully'});
      }
      return jsonResponse({'success': false, 'message': 'Route not found'}, 404);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Déconnexion'));
      await tester.pumpAndSettle();
    }, () => client);

    expect(calls, contains('POST /api/auth/logout'));
    expect(jsonDecode(logoutBody!), {'refreshToken': 'refresh-1'});
    expect(find.text('Connexion'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('jwt_token'), isNull);
  });
}
