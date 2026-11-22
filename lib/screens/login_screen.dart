import 'package:flutter/material.dart';
import '../services/xtream_service.dart';
import '../widgets/tv_field.dart';

class LoginScreen extends StatefulWidget {
  final void Function(XtreamService) onLoggedIn;
  const LoginScreen({super.key, required this.onLoggedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _url = '', _user = '', _pass = '';
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (_url.trim().isEmpty || _user.trim().isEmpty || _pass.isEmpty) {
      setState(() => _error = 'Remplis les 3 champs');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final s = XtreamService(
        serverUrl: _url, username: _user.trim(), password: _pass);
    try {
      await s.login();
      widget.onLoggedIn(s);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: FocusTraversalGroup(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('PRO MAX TV',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const SizedBox(height: 24),
                  TvField(
                    label: 'URL du serveur',
                    hint: 'http://exemple.com:8080',
                    value: _url,
                    keyboardType: TextInputType.url,
                    onChanged: (v) => setState(() => _url = v),
                  ),
                  TvField(
                    label: 'Utilisateur',
                    value: _user,
                    onChanged: (v) => setState(() => _user = v),
                  ),
                  TvField(
                    label: 'Mot de passe',
                    value: _pass,
                    obscure: true,
                    onChanged: (v) => setState(() => _pass = v),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(_error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Se connecter'),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
