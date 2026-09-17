import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration chargee depuis le fichier .env a la racine du projet.
class Env {
  /// A appeler une seule fois au demarrage (dans main()).
  static Future<void> load() => dotenv.load(fileName: '.env');

  /// URL de base de l'API backend (ex: http://10.0.2.2:3000/api)
  static String get apiBaseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000/api';
}
