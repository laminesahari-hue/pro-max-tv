import 'package:flutter/material.dart';
import '../core/profile.dart';
import '../services/source.dart';
import '../widgets/tv_field.dart';

class ProfileFormScreen extends StatefulWidget {
  final void Function(Profile) onSave;
  final bool first;
  const ProfileFormScreen({super.key, required this.onSave, this.first = false});

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  String _type = 'xtream';
  String _name = '', _url = '', _user = '', _pass = '', _mac = '';
  bool _loading = false;
  String? _error;

  String _defaultName() {
    final h = Uri.tryParse(_url.trim())?.host ?? '';
    return h.isEmpty ? 'Ma source' : h;
  }

  Future<void> _submit() async {
    final mac = _mac.trim().toUpperCase();
    if (_url.trim().isEmpty) {
      setState(() => _error = "L'adresse est obligatoire");
      return;
    }
    if (_type == 'xtream' && (_user.trim().isEmpty || _pass.isEmpty)) {
      setState(() => _error = 'Utilisateur et mot de passe obligatoires');
      return;
    }
    if (_type == 'mag' &&
        !RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(mac)) {
      setState(() => _error = 'Adresse MAC invalide (00:1A:79:XX:XX:XX)');
      return;
    }
    final p = Profile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.trim().isEmpty ? _defaultName() : _name.trim(),
      type: _type,
      url: _url.trim(),
      user: _user.trim(),
      pass: _pass,
      mac: mac,
    );
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await buildSource(p).validate();
      widget.onSave(p);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: widget.first ? null : AppBar(title: const Text('Ajouter une source')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: FocusTraversalGroup(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.first) ...[
                    Text('PRO MAX TV',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900, letterSpacing: 2)),
                    const SizedBox(height: 20),
                  ],
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'xtream', label: Text('Xtream')),
                      ButtonSegment(value: 'm3u', label: Text('M3U')),
                      ButtonSegment(value: 'mag', label: Text('MAG')),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() {
                      _type = s.first;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  TvField(
                    label: 'Nom (facultatif)',
                    value: _name,
                    onChanged: (v) => setState(() => _name = v),
                  ),
                  TvField(
                    label: _type == 'm3u'
                        ? 'URL de la playlist'
                        : _type == 'mag'
                            ? 'URL du portail'
                            : 'URL du serveur',
                    hint: _type == 'm3u'
                        ? 'http://exemple.com/liste.m3u'
                        : _type == 'mag'
                            ? 'http://exemple.com/c/'
                            : 'http://exemple.com:8080',
                    value: _url,
                    keyboardType: TextInputType.url,
                    onChanged: (v) => setState(() => _url = v),
                  ),
                  if (_type == 'xtream') ...[
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
                  ],
                  if (_type == 'mag')
                    TvField(
                      label: 'Adresse MAC',
                      hint: '00:1A:79:XX:XX:XX',
                      value: _mac,
                      onChanged: (v) => setState(() => _mac = v),
                    ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.redAccent)),
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
                          : const Text('Ajouter'),
                    ),
                  ),
                  if (widget.first) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.live_tv),
                        label: const Text('Essayer les chaînes gratuites'),
                        onPressed: () => widget.onSave(const Profile(
                            id: 'free', name: 'Chaînes gratuites', type: 'free')),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      );
}
