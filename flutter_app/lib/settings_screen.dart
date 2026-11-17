import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'api/webapp.dart';
import 'listings.dart';
import 'sync.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.initial,
    this.initialError,
    this.shared,
    this.sendTestNotification,
    this.notificationsEnabled = true,
    this.changeNotifications,
    this.readLastNotificationPull,
    this.openSystemSettings,
    required this.save,
  });
  final WebappSettings? initial;
  final String? initialError;
  final SharedState? shared;
  final Future<void> Function(WebappSettings settings) save;
  final Future<void> Function(WebappSettings settings)? sendTestNotification;
  final bool notificationsEnabled;
  final Future<bool> Function(bool)? changeNotifications;
  final Future<DateTime?> Function()? readLastNotificationPull;
  final Future<void> Function()? openSystemSettings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final address = TextEditingController(
    text: widget.initial?.endpoint.toString(),
  );
  late final token = TextEditingController(text: widget.initial?.token);
  late String? feedback = widget.initialError;
  bool success = false;
  bool busy = false;
  late bool notificationsEnabled = widget.notificationsEnabled;
  DateTime? lastNotificationPull;
  Timer? refreshNotifications;

  @override
  void initState() {
    super.initState();
    unawaited(readNotificationTime());
    if (widget.readLastNotificationPull != null) {
      refreshNotifications = Timer.periodic(
        const Duration(seconds: 15),
        (_) => unawaited(readNotificationTime()),
      );
    }
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.notificationsEnabled != oldWidget.notificationsEnabled) {
      notificationsEnabled = widget.notificationsEnabled;
    }
  }

  Future<void> readNotificationTime() async {
    try {
      final value = await widget.readLastNotificationPull?.call();
      if (mounted && value != lastNotificationPull) {
        setState(() => lastNotificationPull = value);
      }
    } on Exception {
      // Keep the last displayed timestamp if local storage is temporarily unavailable.
    }
  }

  @override
  void dispose() {
    refreshNotifications?.cancel();
    address.dispose();
    token.dispose();
    super.dispose();
  }

  Future<void> submit({required bool save}) async {
    setState(() {
      feedback = null;
      busy = true;
      success = false;
    });
    try {
      final settings = WebappSettings(address.text, token.text);
      if (save) {
        await widget.save(settings);
      } else {
        await WebappClient(settings).ping();
        if (mounted) {
          setState(() {
            success = true;
            feedback = 'A kapcsolat működik.';
          });
        }
      }
    } on AppFailure catch (error) {
      if (mounted) setState(() => feedback = error.message);
    } on Exception {
      if (mounted) {
        setState(() => feedback = 'A beállításokat nem sikerült menteni.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> testNotification() async {
    setState(() {
      feedback = null;
      busy = true;
      success = false;
    });
    try {
      final settings = WebappSettings(address.text, token.text);
      await widget.sendTestNotification!(settings);
      await readNotificationTime();
      if (mounted) {
        setState(() {
          success = true;
          feedback = 'A próbaértesítés megjelent az eszközön.';
        });
      }
    } on AppFailure catch (error) {
      if (mounted) setState(() => feedback = error.message);
    } on Exception {
      if (mounted) {
        setState(() => feedback = 'A próbaértesítés küldése sikertelen.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> toggleNotifications(bool enabled) async {
    setState(() {
      busy = true;
      feedback = null;
      success = false;
    });
    try {
      final value = await widget.changeNotifications!(enabled);
      if (mounted) setState(() => notificationsEnabled = value);
      await readNotificationTime();
    } on AppFailure catch (error) {
      if (mounted) setState(() => feedback = error.message);
    } on Exception {
      if (mounted) {
        setState(
          () => feedback = 'Az értesítési beállítást nem sikerült módosítani.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openAndroidSettings() async {
    try {
      await widget.openSystemSettings!();
    } on Exception {
      if (mounted) {
        setState(() {
          success = false;
          feedback = 'A rendszerbeállítások nem nyithatók meg.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Console Deal Finder')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 38, 20, 24),
              children: [
                Text('Beállítások', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Add meg a telepített Apps Script webapp címét és kliens-tokenjét.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                if (widget.shared case final shared?) ...[
                  ListenableBuilder(
                    listenable: shared,
                    builder: (context, _) => Text(
                      shared.localSaveFailed
                          ? 'A helyi mentés sikertelen.'
                          : shared.pending
                          ? 'Nem szinkronizált változások'
                          : shared.syncFailed
                          ? 'A szinkron nem érhető el.'
                          : shared.lastSync == null
                          ? 'Szinkronizálásra vár'
                          : 'Szinkronizálva: ${dateLabel(shared.lastSync!)}',
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: address,
                          enabled: !busy,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'Webapp-cím',
                            helperText: 'A /exec végű cím',
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: token,
                          enabled: !busy,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Kliens-token',
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (busy) const LinearProgressIndicator(),
                        if (feedback != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                feedback!,
                                style: TextStyle(
                                  color: success
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            OutlinedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => submit(save: false),
                              icon: const Icon(Icons.lan_outlined),
                              label: const Text('Kapcsolat tesztelése'),
                            ),
                            FilledButton.icon(
                              onPressed: busy ? null : () => submit(save: true),
                              icon: const Icon(Icons.check),
                              label: const Text('Mentés'),
                            ),
                          ],
                        ),
                        if (widget.changeNotifications != null) ...[
                          const Divider(height: 32),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Értesítések'),
                            value: notificationsEnabled,
                            onChanged: busy ? null : toggleNotifications,
                          ),
                          Text(
                            'Utolsó sikeres értesítés-lekérés: ${lastNotificationPull == null ? 'Még nem történt' : dateLabel(lastNotificationPull!)}',
                          ),
                        ],
                        if (widget.sendTestNotification != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: busy || !notificationsEnabled
                                  ? null
                                  : testNotification,
                              icon: const Icon(Icons.notifications_outlined),
                              label: const Text('Próbaértesítés'),
                            ),
                          ),
                        if (widget.openSystemSettings != null) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Xiaomi telefonon kapcsold be az Automatikus indítást, az akkumulátor-beállításnál pedig válaszd a Nincs korlátozás lehetőséget.',
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: openAndroidSettings,
                              child: const Text(
                                'Alkalmazás rendszerbeállításai',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
