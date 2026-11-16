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
    required this.save,
  });
  final WebappSettings? initial;
  final String? initialError;
  final SharedState? shared;
  final Future<void> Function(WebappSettings settings) save;
  final Future<void> Function(WebappSettings settings)? sendTestNotification;

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

  @override
  void dispose() {
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
      if (widget.sendTestNotification case final send?) {
        await send(settings);
      } else {
        await WebappClient(settings).notifyTest();
      }
      if (mounted) {
        setState(() {
          success = true;
          feedback = 'A próbaértesítést elküldtük.';
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
                            OutlinedButton.icon(
                              onPressed: busy ? null : testNotification,
                              icon: const Icon(Icons.notifications_outlined),
                              label: const Text('Próbaértesítés küldése'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Az értesítésekhez iratkozz fel az ntfy appban arra a csatornára, '
                          'amelynek neve az Apps Script Script Properties beállításaiban található.',
                        ),
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
