// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// CORREÇÃO: O nome do seu pacote é 'lit', não 'mylitapp'
import 'package:lit/main.dart'; 

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // O 'MyApp' agora é encontrado porque o import está correto
    await tester.pumpWidget(const MyApp());

    // Verify that our counter starts at 0.
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    // Tap the '+' icon and trigger a frame.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // Verify that our counter has incremented.
    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}
// ```

// ---

// ### 3. Próximos Passos (Para Fazer Funcionar)

// Depois de salvar esses dois arquivos (`lib/main.dart` e `test/widget_test.dart`):

// 1.  **Garanta as Dependências:** Abra o terminal e rode `flutter pub get` (para garantir que `flutter_speed_dial` e `flutter_hooks` estão 100% instalados).
// 2.  **Rode o Build Runner (MUITO IMPORTANTE):** Este é o passo que corrige o erro `UserProfileAdapter isn't defined` e `main.g.dart`.
//     ```bash
//     dart run build_runner build --delete-conflicting-outputs
    
