import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _id = TextEditingController();
  final _pw = TextEditingController();
  final _code = TextEditingController();
  bool _recovery = false;
  late final TextEditingController _api;
  late final TextEditingController _sync;
  bool _busy = false;
  bool _showServer = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().api.servers;
    _api = TextEditingController(text: s.api);
    _sync = TextEditingController(text: s.sync);
  }

  Future<void> _submit() async {
    if (_id.text.trim().isEmpty || _pw.text.isEmpty) {
      setState(() => _error = 'Enter your email or phone number and your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppState>();
    await app.setServers(_api.text, _sync.text);
    final err = await app.signIn(_id.text, _pw.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  Future<void> _submitCode() async {
    final code = _code.text.trim();
    final ok = _recovery ? code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length == 10 : RegExp(r'^\d{6}$').hasMatch(code.replaceAll(' ', ''));
    if (!ok) {
      setState(() => _error = _recovery ? 'Enter one of your recovery codes, like ABCDE-FGHJK.' : 'Enter the 6-digit code from your authenticator app.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AppState>().signInWithCode(code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
      if (err != null) _code.clear();
    });
  }

  /// Shown after a correct password when the account uses two-step sign-in.
  Widget _codeStep(AppState app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Enter your code', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(_recovery
            ? 'Type one of the recovery codes you saved. Each one works once.'
            : 'Open your authenticator app and type the 6-digit code for Osun EduOS.'),
        const SizedBox(height: 16),
        TextField(
          key: const Key('code'),
          controller: _code,
          autofocus: true,
          keyboardType: _recovery ? TextInputType.text : TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          decoration: InputDecoration(labelText: _recovery ? 'Recovery code' : 'Code', hintText: _recovery ? 'ABCDE-FGHJK' : '123456'),
          onSubmitted: (_) => _submitCode(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: bad)),
        ],
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _submitCode, child: Text(_busy ? 'Checking…' : 'Sign in')),
        TextButton(
          onPressed: () => setState(() {
            _recovery = !_recovery;
            _code.clear();
            _error = null;
          }),
          child: Text(_recovery ? 'Use my authenticator app' : 'Use a recovery code'),
        ),
        TextButton(
          onPressed: () {
            _code.clear();
            setState(() => _error = null);
            app.cancelCode();
          },
          child: const Text('Start again'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: indigo, borderRadius: BorderRadius.circular(12)),
                      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Osun EduOS', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                        Text('Teacher app', style: TextStyle(color: Color(0xFFC3C9F0))),
                      ]),
                    ),
                    const SizedBox(height: 24),
                    if (app.codeChallenge != null) _codeStep(app) else ...[
                      Text('Sign in', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      const Text('Use the account your school administrator gave you. Registers and scores work without internet once you have signed in.'),
                      if (app.pending > 0) ...[
                        const SizedBox(height: 12),
                        Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('${app.pending} change${app.pending == 1 ? ' is' : 's are'} saved on this phone and will be sent after you sign in.'))),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('identifier'),
                        controller: _id,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(labelText: 'Email or phone number'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('password'),
                        controller: _pw,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        decoration: const InputDecoration(labelText: 'Password'),
                        onSubmitted: (_) => _submit(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: bad)),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Signing in…' : 'Sign in')),
                      const SizedBox(height: 8),
                      TextButton(onPressed: () => setState(() => _showServer = !_showServer), child: Text(_showServer ? 'Hide server settings' : 'Server settings')),
                      if (_showServer) ...[
                        TextField(controller: _api, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'EduOS API address')),
                        const SizedBox(height: 8),
                        TextField(controller: _sync, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Sync service address')),
                      ],
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

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  String? _problem() {
    final p = _next.text;
    if (_current.text.isEmpty) return 'Enter the temporary password you were given.';
    if (p.runes.length < 12) return 'Use at least 12 characters. A short phrase of three or four words is easy to remember.';
    if (p.runes.length > 128) return 'Use 128 characters or fewer.';
    if (p != _again.text) return 'The new passwords do not match.';
    if (p == _current.text) return 'Choose a password different from the temporary one.';
    return null;
  }

  Future<void> _submit() async {
    final p = _problem();
    if (p != null) return setState(() => _error = p);
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AppState>().changePassword(_current.text, _next.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Choose your password')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('You signed in with a temporary password. Choose your own to continue. Keep it private.'),
          const SizedBox(height: 16),
          TextField(controller: _current, obscureText: true, decoration: const InputDecoration(labelText: 'Temporary password')),
          const SizedBox(height: 12),
          TextField(controller: _next, obscureText: true, decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 12 characters, for example a phrase of three or four words', helperMaxLines: 2)),
          const SizedBox(height: 12),
          TextField(controller: _again, obscureText: true, decoration: const InputDecoration(labelText: 'New password again')),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: bad))),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Saving…' : 'Save password')),
        ]),
      );
}
