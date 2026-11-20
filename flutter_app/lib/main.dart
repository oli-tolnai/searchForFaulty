import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import 'api/models.dart';
import 'api/webapp.dart';
import 'listing_card.dart';
import 'local_notifications.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'group_results.dart';
import 'storage.dart';
import 'app_theme.dart';
import 'sync.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ConsoleDealFinder());
}

class ConsoleDealFinder extends StatelessWidget {
  const ConsoleDealFinder({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Console Deal Finder',
      debugShowCheckedModeBanner: false,
      locale: const Locale('hu'),
      supportedLocales: const [Locale('hu')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: Ui.theme,
      home: const _Home(),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> with WidgetsBindingObserver {
  final settingsStore = const SettingsStore();
  SearchCache cache = const SearchCache();
  SharedState? shared;
  WebappClient? client;
  WebappSettings? settings;
  SearchResult? cached;
  GroupResults cachedGroups = GroupResults();
  String? settingsError;
  bool loading = true;
  final localNotifications = LocalNotifications();
  final watchNavigation = ValueNotifier<int>(0);
  DeliveryFiles? deliveryFiles;
  Timer? notificationTimer;
  Future<void>? polling;
  bool notificationsEnabled = true;
  bool openWatchesOnLaunch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    restore();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) pollQuietly();
  }

  Future<void> startNotifications() async {
    try {
      final files = await DeliveryFiles.open();
      await files.deviceId(create: true);
      final enabled = await files.enabled();
      if (!mounted) return;
      setState(() {
        deliveryFiles = files;
        notificationsEnabled = enabled;
      });
      await localNotifications.initialize(onNotificationTap);
      if (Platform.isAndroid && !await files.permissionExplained() && mounted) {
        await files.markPermissionExplained();
        if (notificationsEnabled && !await allowAndroidNotifications()) {
          notificationsEnabled = false;
          await files.setEnabled(false);
        }
      }
      await configureNotificationTask(notificationsEnabled);
    } on Exception {
      // Search and saved state remain available if the notification plugin fails.
    }
    if (!mounted) return;
    setState(() {});
    pollQuietly();
    if (Platform.isWindows) {
      notificationTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => pollQuietly(),
      );
    }
  }

  Future<bool> allowAndroidNotifications() async {
    if (!Platform.isAndroid || await localNotifications.allowed()) return true;
    if (!mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Értesítések engedélyezése'),
        content: const Text(
          'A figyelt aukciók és az új találatok jelzéséhez engedélyezd az értesítéseket az Androidon.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Később'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tovább'),
          ),
        ],
      ),
    );
    return accepted == true && await localNotifications.requestPermission();
  }

  void onNotificationTap(String? payload) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final url = notificationListingLink(payload);
      if (url != null) {
        unawaited(openExternal(context, url));
      } else {
        Navigator.of(context).popUntil((route) => route.isFirst);
        openWatchesOnLaunch = true;
        watchNavigation.value++;
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> pollNotifications(WebappClient active, DeliveryFiles files) =>
      polling ??= localNotifications
          .poll(active, files)
          .whenComplete(() => polling = null);

  void pollQuietly() {
    final active = client;
    final files = deliveryFiles;
    if (active == null || files == null) return;
    unawaited(pollNotifications(active, files).catchError((Object _) {}));
  }

  Future<bool> setNotificationsEnabled(bool enabled) async {
    final files = deliveryFiles;
    if (files == null) return false;
    if (enabled && !await allowAndroidNotifications()) {
      throw const AppFailure(
        'Az Android rendszerbeállításaiban engedélyezd az értesítéseket.',
      );
    }
    await files.setEnabled(enabled);
    if (mounted) setState(() => notificationsEnabled = enabled);
    await configureNotificationTask(enabled);
    if (enabled) pollQuietly();
    return enabled;
  }

  Future<void> sendTestNotification(WebappSettings value) async {
    final files = deliveryFiles;
    if (files == null ||
        !await files.enabled() ||
        !await localNotifications.allowed()) {
      throw const AppFailure('A próba előtt engedélyezd az értesítéseket.');
    }
    final stateId = settings?.endpoint == value.endpoint
        ? settings!.stateId
        : value.stateId;
    final active = WebappClient(
      WebappSettings(value.endpoint.toString(), value.token, stateId: stateId),
    );
    final id = await active.notifyTest();
    // A concurrently running foreground poll may have started before the test was queued.
    await polling?.catchError((Object _) {});
    for (var attempt = 0; attempt < 2 && !await files.wasShown(id); attempt++) {
      await pollNotifications(active, files);
    }
    if (!await files.wasShown(id)) {
      throw const AppFailure(
        'A próbaértesítés a sorban van. A következő lekéréskor jelenhet meg.',
      );
    }
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(startNotifications());
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
    final nextGroups = sameProject
        ? cachedGroups
        : await nextCache.readGroups();
    final nextResult = sameProject ? cached : null;
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
    cachedGroups = nextGroups;
    unawaited(next.sync());
    pollQuietly();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    notificationTimer?.cancel();
    watchNavigation.dispose();
    shared?.dispose();
    super.dispose();
  }

  void openSettings() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (page) => SettingsScreen(
        initial: settings,
        shared: shared,
        notificationsEnabled: notificationsEnabled,
        changeNotifications: setNotificationsEnabled,
        readLastNotificationPull: () async =>
            deliveryFiles?.lastPull(settings!.stateId),
        openSystemSettings: Platform.isAndroid ? openAndroidAppSettings : null,
        sendTestNotification: sendTestNotification,
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
      return SettingsScreen(
        initialError: settingsError,
        save: save,
        notificationsEnabled: notificationsEnabled,
        changeNotifications: setNotificationsEnabled,
        openSystemSettings: Platform.isAndroid ? openAndroidAppSettings : null,
      );
    }
    return SearchScreen(
      key: ValueKey(settings!.stateId),
      initial: cached,
      initialGroups: cachedGroups,
      saveGroups: (groups) async {
        cachedGroups = groups;
        await cache.writeGroups(groups);
      },
      loadConfig: client!.ping,
      search: client!.search,
      loadDetails: client!.details,
      sanitize: settings!.safeText,
      saveResult: cache.write,
      openSettings: openSettings,
      settingsPage: (navigation, openHidden) => SettingsScreen(
        openHidden: openHidden,
        initial: settings,
        shared: shared,
        navigation: navigation,
        notificationsEnabled: notificationsEnabled,
        changeNotifications: setNotificationsEnabled,
        readLastNotificationPull: () async =>
            deliveryFiles?.lastPull(settings!.stateId),
        openSystemSettings: Platform.isAndroid ? openAndroidAppSettings : null,
        sendTestNotification: sendTestNotification,
        save: save,
      ),
      shared: shared,
      openWatchesInitially: openWatchesOnLaunch,
      watchNavigation: watchNavigation,
    );
  }
}
