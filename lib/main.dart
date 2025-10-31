import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lit/models.dart'; // Importa os modelos
import 'package:lit/pages/home_page.dart'; // Importa a nova HomePage

// --- Constantes de Tema (Estilo Liquid Glass) ---
const Color kBackgroundColor =
    Color(0xFF000814); // Azul muito escuro para fundo
const Color kCardColor =
    Color(0xFF1A1F29); // Azul acinzentado escuro para cards
const Color kAccentColor = Color(0xFF4CC2FF); // Azul claro vibrante
const Color kTextPrimary = Color(0xFFFFFFFF); // Branco puro para contraste
const Color kTextSecondary = Color(0xFFADB7BE); // Cinza azulado suave
const Color kRedColor = Color(0xFFFF3B30); // Vermelho iOS
const Color kYellowColor = Color(0xFFFFD60A); // Amarelo vibrante

// --- Inicialização ---
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appDocumentDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocumentDir.path);

  // Registra os adaptadores
  Hive.registerAdapter(TaskAdapter());
  Hive.registerAdapter(NoteAdapter());
  Hive.registerAdapter(UserProfileAdapter());

  // Abre as caixas
  await Hive.openBox<Task>(tasksBoxName);
  await Hive.openBox<Note>(notesBoxName);
  await Hive.openBox<UserProfile>(profileBoxName);

  final profileBox = Hive.box<UserProfile>(profileBoxName);
  if (profileBox.isEmpty) {
    profileBox.put(
        profileKey, UserProfile(totalXP: 0.0, level: 1, playerName: "Player"));
  }

  runApp(const MyApp());
}

// --- App Widget (Apenas Tema) ---
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LIT V0.5.0', // Nova versão
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true, // Habilita Material 3
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: kBackgroundColor,

        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),

        cardTheme: CardThemeData(
          color:
              kCardColor.withAlpha((0.65 * 255).round()), // Mais transparente
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), // Mais arredondado
            side: BorderSide(
              color: kTextPrimary.withAlpha(15), // Borda mais sutil e clara
              width: 0.5,
            ),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),

        dialogTheme: DialogThemeData(
          backgroundColor: kCardColor.withAlpha((0.75 * 255).round()),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: kTextPrimary.withAlpha(15), width: 0.5),
          ),
        ),

        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: kCardColor.withAlpha((0.75 * 255).round()),
          modalBackgroundColor: kCardColor.withAlpha((0.85 * 255).round()),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
        ),

        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: kAccentColor.withAlpha((0.9 * 255).round()),
          foregroundColor: kTextPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: kTextPrimary.withAlpha(25), width: 0.5),
          ),
        ),

        tabBarTheme: const TabBarThemeData(
          labelColor: kAccentColor, // Cor de acento
          unselectedLabelColor: kTextSecondary,
          indicatorColor: kAccentColor,
          indicatorSize: TabBarIndicatorSize.tab,
        ),

        drawerTheme: const DrawerThemeData(
          backgroundColor: kCardColor,
        ),

        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: kTextPrimary.withAlpha(15), width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: kAccentColor.withAlpha(150), width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: kTextPrimary.withAlpha(15), width: 0.5),
          ),
          filled: true,
          fillColor: kCardColor.withAlpha((0.3 * 255).round()),
          hintStyle: TextStyle(color: kTextSecondary.withAlpha(150)),
          labelStyle: const TextStyle(color: kTextPrimary),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),

        checkboxTheme: CheckboxThemeData(
          fillColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return kAccentColor.withAlpha((0.9 * 255).round());
            }
            return kCardColor.withAlpha((0.5 * 255).round());
          }),
          checkColor: MaterialStateProperty.all(kTextPrimary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          side: BorderSide(color: kTextPrimary.withAlpha(50), width: 1),
        ),

        chipTheme: ChipThemeData(
          backgroundColor: kTextSecondary.withAlpha(30),
          disabledColor: kTextSecondary.withAlpha(10),
          selectedColor: kAccentColor.withAlpha(80),
          secondarySelectedColor: Colors.teal.withAlpha(80),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          labelStyle: const TextStyle(color: kTextPrimary, fontSize: 12),
          secondaryLabelStyle:
              const TextStyle(color: Colors.white, fontSize: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          checkmarkColor: kAccentColor,
          side: BorderSide(color: kTextSecondary.withAlpha(50)),
        ),

        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: kTextSecondary,
          ),
        ),

        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: kAccentColor, // Cor de acento
          linearTrackColor: kTextSecondary.withAlpha(50),
          linearMinHeight: 8, // Mais fino, como na sua ref
        ),
      ),
      home: const HomePage(), // Vem do novo arquivo 'home_page.dart'
      debugShowCheckedModeBanner: false,
    );
  }
}
