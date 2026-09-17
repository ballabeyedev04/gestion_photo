import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:photo_app/main.dart';

void main() {
  setUpAll(() {
    // En test on ne lit pas le fichier .env : la config est injectee directement
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:3000/api');
  });

  testWidgets('App starts on the login page', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Connexion'), findsOneWidget);
    expect(find.text('Gestion des Photos'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
  });
}
