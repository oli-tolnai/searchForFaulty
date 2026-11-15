import 'package:material_ui/material_ui.dart';

import 'api/webapp.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.initial,
    this.initialError,
    required this.save,
  });
  final WebappSettings? initial;
  final String? initialError;
  final Future<void> Function(WebappSettings settings) save;

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
