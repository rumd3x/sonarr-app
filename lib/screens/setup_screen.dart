import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/app_state.dart';
import '../services/settings.dart';

/// First-launch setup and also used for editing the connection later.
class SetupScreen extends StatefulWidget {
  final bool editing;
  const SetupScreen({super.key, this.editing = false});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _primary;
  late final TextEditingController _secondary;
  late final TextEditingController _key;
  bool _busy = false;
  bool _hideKey = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.editing ? context.read<AppState>().config : null;
    _primary = TextEditingController(text: c?.primaryUrl ?? '');
    _secondary = TextEditingController(text: c?.secondaryUrl ?? '');
    _key = TextEditingController(text: c?.apiKey ?? '');
  }

  @override
  void dispose() {
    _primary.dispose();
    _secondary.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final cfg = ServerConfig(
      primaryUrl: ServerConfig.normalizeUrl(_primary.text),
      secondaryUrl: ServerConfig.normalizeUrl(_secondary.text),
      apiKey: _key.text.trim(),
    );
    final probe = SonarrApi(cfg);
    final state = context.read<AppState>();
    final nav = Navigator.of(context);
    try {
      await probe.systemStatus();
      await state.setConfig(cfg);
      if (widget.editing) nav.pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      probe.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _urlValidator(String? v, {bool required = true}) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return required ? 'Required' : null;
    final u = Uri.tryParse(ServerConfig.normalizeUrl(s));
    if (u == null || u.host.isEmpty) return 'Invalid URL';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: widget.editing ? AppBar(title: const Text('Connection')) : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!widget.editing) ...[
                      Image.asset('assets/branding/logo.png', height: 96),
                      const SizedBox(height: 12),
                      Text(
                        'Sonarr',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Unofficial companion app',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 32),
                    ],
                    TextFormField(
                      controller: _primary,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Primary URL',
                        hintText: 'http://192.168.1.10:8989',
                        prefixIcon: Icon(Icons.dns_outlined),
                      ),
                      validator: _urlValidator,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _secondary,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Secondary URL (fallback)',
                        hintText: 'https://sonarr.example.com',
                        prefixIcon: Icon(Icons.public),
                        helperText: 'Used when the primary URL is unreachable',
                      ),
                      validator: (v) => _urlValidator(v, required: false),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _key,
                      obscureText: _hideKey,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'API key',
                        helperText: 'Sonarr → Settings → General → Security',
                        prefixIcon: const Icon(Icons.key),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _hideKey ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () => setState(() => _hideKey = !_hideKey),
                        ),
                      ),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Required' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: cs.error)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(widget.editing ? 'Save' : 'Connect'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                    if (!widget.editing) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => context.read<AppState>().setConfig(
                                ServerConfig.demo,
                              ),
                        icon: const Icon(Icons.science_outlined),
                        label: const Text('Try demo'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Explore the app with built-in sample data. '
                        'No server needed.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
