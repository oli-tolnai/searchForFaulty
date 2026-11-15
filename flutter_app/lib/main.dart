import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import 'api/models.dart';
import 'api/webapp.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'storage.dart';
import 'sync.dart';

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
  SearchCache cache = const SearchCache();
  SharedState? shared;
  WebappClient? client;
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
    WebappSettings? restored;
    String? error;
    try {
      restored = await settingsStore.read();
    } on Exception {
      error =
          'A mentett kapcsolat nem olvasható. Add meg újra a beállításokat.';
    }
    if (restored != null) await connect(restored);
    if (mounted) {
      setState(() {
        settingsError = error;
        loading = false;
      });
    }
  }

  Future<void> save(WebappSettings value) async {
    final sameProject = settings?.endpoint == value.endpoint;
    final random = Random.secure();
    final id = sameProject
        ? settings!.stateId
        : List.generate(24, (_) => random.nextInt(16).toRadixString(16)).join();
    final next = WebappSettings(
      value.endpoint.toString(),
      value.token,
      stateId: id,
    );
    await settingsStore.write(next);
    await connect(next, sameProject: sameProject);
    if (mounted) setState(() {});
  }

  Future<void> connect(WebappSettings value, {bool sameProject = false}) async {
    final nextClient = WebappClient(value);
    final store = SharedStateStore(value.stateId);
    SharedState create(Json? restored) => SharedState(
      readRemote: nextClient.getState,
      writeRemote: nextClient.applyState,
      refreshRemote: nextClient.refreshFavorites,
      save: store.write,
      restored: restored,
    );
    if (sameProject && shared != null) {
      await shared!.sync();
    }
    SharedState next;
    try {
      next = create(await store.read());
    } on Exception {
      next = create(null);
    }
    final nextCache = SearchCache(value.stateId);
    final nextResult = sameProject ? cached : await nextCache.read();
    if (!mounted) {
      next.dispose();
      return;
    }
    shared?.dispose();
    shared = next;
    settings = value;
    client = nextClient;
    cache = nextCache;
    cached = nextResult;
    unawaited(next.sync());
  }

  @override
  void dispose() {
    shared?.dispose();
    super.dispose();
  }

  void openSettings() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (page) => SettingsScreen(
        initial: settings,
        shared: shared,
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
    return SearchScreen(
      key: ValueKey(settings!.stateId),
      initial: cached,
      search: client!.search,
      loadDetails: client!.details,
      sanitize: settings!.safeText,
      saveResult: cache.write,
      openSettings: openSettings,
      shared: shared,
    );
  }
}
