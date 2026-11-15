import 'package:material_ui/material_ui.dart';

import 'api/models.dart';
import 'api/webapp.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ConsoleDealFinder());
}

class ConsoleDealFinder extends StatelessWidget {
  const ConsoleDealFinder({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xffb9ee7b),
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xffb9ee7b),
          onPrimary: const Color(0xff18280c),
          surface: const Color(0xff191e27),
          outlineVariant: const Color(0xff303847),
        );
    return MaterialApp(
      title: 'Console Deal Finder',
      debugShowCheckedModeBanner: false,
      locale: const Locale('hu'),
      supportedLocales: const [Locale('hu')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xff101319),
        cardTheme: CardThemeData(
          color: scheme.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xff101319)),
      ),
      home: const _Home(),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  final settingsStore = const SettingsStore();
  final cache = const SearchCache();
  WebappSettings? settings;
  SearchResult? cached;
  String? settingsError;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    final pendingCache = cache.read();
    WebappSettings? restored;
    String? error;
    try {
      restored = await settingsStore.read();
    } on Exception {
      error =
          'A mentett kapcsolat nem olvasható. Add meg újra a beállításokat.';
    }
    final result = await pendingCache;
    if (mounted) {
      setState(() {
        settings = restored;
        cached = result;
        settingsError = error;
        loading = false;
      });
    }
  }

  Future<void> save(WebappSettings value) async {
    await settingsStore.write(value);
    if (mounted) setState(() => settings = value);
  }

  void openSettings() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (page) => SettingsScreen(
        initial: settings,
        save: (value) async {
          await save(value);
          if (page.mounted) Navigator.of(page).pop();
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (settings == null) {
      return SettingsScreen(initialError: settingsError, save: save);
    }
    final client = WebappClient(settings!);
    return SearchScreen(
      initial: cached,
      search: client.search,
      loadDetails: client.details,
      sanitize: settings!.safeText,
      saveResult: cache.write,
      openSettings: openSettings,
    );
  }
}
