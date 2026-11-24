import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
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

  HttpServer? _server;
  String? _qrUrl;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _startQrReceiver();
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  Future<String?> _findLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback &&
              (addr.address.startsWith('192.168.') ||
                  addr.address.startsWith('10.') ||
                  addr.address.startsWith('172.'))) {
            return addr.address;
          }
        }
      }
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _startQrReceiver() async {
    try {
      final ip = await _findLocalIp();
      if (ip == null || !mounted) return;
      final srv = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _server = srv;
      if (mounted) {
        setState(() => _qrUrl = 'http://$ip:${srv.port}');
      }

      srv.listen((HttpRequest req) async {
        try {
          if (req.method == 'GET') {
            req.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.html
              ..write(_mobileWebPage());
            await req.response.close();
          } else if (req.method == 'POST' && req.uri.path == '/submit') {
            final body = await utf8.decoder.bind(req).join();
            final data = jsonDecode(body) as Map<String, dynamic>;
            final type = (data['type'] ?? 'xtream').toString();
            final name = (data['name'] ?? '').toString().trim();
            final url = (data['url'] ?? '').toString().trim();
            final user = (data['user'] ?? '').toString().trim();
            final pass = (data['pass'] ?? '').toString();
            final mac = (data['mac'] ?? '').toString().trim().toUpperCase();

            if (url.isEmpty) {
              req.response
                ..statusCode = HttpStatus.badRequest
                ..headers.contentType = ContentType.json
                ..write(jsonEncode({'ok': false, 'error': 'URL obligatoire'}));
              await req.response.close();
              return;
            }

            final h = Uri.tryParse(url)?.host ?? '';
            final p = Profile(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              name: name.isEmpty ? (h.isEmpty ? 'Ma source' : h) : name,
              type: type,
              url: url,
              user: user,
              pass: pass,
              mac: mac,
            );

            await buildSource(p).validate();

            req.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'ok': true}));
            await req.response.close();

            if (mounted) {
              setState(() {
                _type = type;
                _name = p.name;
                _url = url;
                _user = user;
                _pass = pass;
                _mac = mac;
                _error = null;
              });
              widget.onSave(p);
            }
          } else {
            req.response.statusCode = HttpStatus.notFound;
            await req.response.close();
          }
        } catch (e) {
          try {
            req.response
              ..statusCode = HttpStatus.badRequest
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({
                'ok': false,
                'error': e.toString().replaceFirst('Exception: ', ''),
              }));
            await req.response.close();
          } catch (_) {}
        }
      });
    } catch (_) {}
  }

  String _mobileWebPage() => '''
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Envoyer abonnement vers TV</title>
<style>
  body{font-family:system-ui,-apple-system,sans-serif;background:#0d1015;color:#fff;margin:0;padding:20px;display:flex;justify-content:center}
  .box{width:100%;max-width:420px;background:#161b22;border:1px solid #2b323d;border-radius:16px;padding:20px}
  h2{margin:0 0 6px;color:#69F028;font-size:20px}
  p{margin:0 0 16px;color:#9aa4b2;font-size:13px}
  .tabs{display:flex;gap:8px;margin-bottom:14px}
  .tab{flex:1;padding:10px;border-radius:10px;border:1px solid #2b323d;background:#0d1015;color:#fff;font-weight:600;cursor:pointer}
  .tab.active{background:#69F028;color:#000;border-color:#69F028}
  label{display:block;font-size:12px;color:#9aa4b2;margin:10px 0 4px}
  input{width:100%;box-sizing:border-box;padding:12px;border-radius:10px;border:1px solid #2b323d;background:#0d1015;color:#fff;font-size:15px}
  button.send{width:100%;margin-top:18px;padding:14px;border:none;border-radius:12px;background:#69F028;color:#000;font-weight:800;font-size:16px;cursor:pointer}
  button.send:disabled{opacity:.6}
  .msg{margin-top:12px;font-size:14px;text-align:center}
</style>
</head>
<body>
<div class="box">
  <h2>Envoyer vers la TV</h2>
  <p>Remplissez votre abonnement sur votre téléphone pour le connecter automatiquement sur la télé.</p>
  <div class="tabs">
    <button type="button" class="tab active" onclick="setType('xtream',this)">Xtream</button>
    <button type="button" class="tab" onclick="setType('m3u',this)">M3U</button>
    <button type="button" class="tab" onclick="setType('mag',this)">MAG</button>
  </div>
  <label>Nom (facultatif)</label>
  <input id="name" placeholder="Mon abonnement">
  <label id="urlLbl">URL du serveur</label>
  <input id="url" type="url" placeholder="http://exemple.com:8080">
  <div id="xtreamFields">
    <label>Utilisateur</label>
    <input id="user" autocomplete="off">
    <label>Mot de passe</label>
    <input id="pass" type="password">
  </div>
  <div id="magFields" style="display:none">
    <label>Adresse MAC</label>
    <input id="mac" placeholder="00:1A:79:XX:XX:XX">
  </div>
  <button id="btn" class="send" onclick="send()">Envoyer sur la TV</button>
  <div id="msg" class="msg"></div>
</div>
<script>
let type='xtream';
function setType(t,el){
  type=t;
  document.querySelectorAll('.tab').forEach(b=>b.classList.remove('active'));
  el.classList.add('active');
  document.getElementById('xtreamFields').style.display=t==='xtream'?'block':'none';
  document.getElementById('magFields').style.display=t==='mag'?'block':'none';
  document.getElementById('urlLbl').innerText=t==='m3u'?'URL de la playlist':(t==='mag'?'URL du portail':'URL du serveur');
  document.getElementById('url').placeholder=t==='m3u'?'http://exemple.com;
}
async function send(){
  const btn=document.getElementById('btn'), msg=document.getElementById('msg');
  btn.disabled=true; msg.style.color='#9aa4b2'; msg.innerText='Connexion en cours sur la TV...';
  try{
    const r=await fetch('/submit',{
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({
        type,
        name:document.getElementById('name').value,
        url:document.getElementById('url').value,
        user:document.getElementById('user').value,
        pass:document.getElementById('pass').value,
        mac:document.getElementById('mac').value
      })
    });
    const j=await r.json();
    if(j.ok){msg.style.color='#69F028';msg.innerText='Abonnement envoyé ! Regardez votre TV.';}
    else{msg.style.color='#ff6b6b';msg.innerText=j.error||'Erreur de connexion';}
  }catch(e){msg.style.color='#ff6b6b';msg.innerText='Impossible de joindre la TV (vérifiez le Wi-Fi)';}
  btn.disabled=false;
}
</script>
</body>
</html>
''';

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

  Widget _buildQrCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.qr_code_scanner, color: Color(0xFF69F028), size: 30),
          const SizedBox(height: 8),
          const Text(
            'Connexion rapide par téléphone',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Scannez ce QR Code avec votre mobile (même Wi-Fi) pour coller votre abonnement.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: QrImageView(
              data: _qrUrl!,
              version: QrVersions.auto,
              size: 175,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _qrUrl!,
            style: const TextStyle(
              color: Color(0xFF69F028),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return FocusTraversalGroup(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (widget.first) ...[
          Text('PRO MAX TV',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 2)),
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
              ? 'http://exemple.com'
              : _type == 'mag'
                  ? 'http://exemple.com'
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 760;
    return Scaffold(
      appBar:
          widget.first ? null : AppBar(title: const Text('Ajouter une source')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: wide && _qrUrl != null
              ? ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(flex: 3, child: _buildForm(context)),
                      const SizedBox(width: 28),
                      Expanded(flex: 2, child: _buildQrCard()),
                    ],
                  ),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildForm(context),
                      if (_qrUrl != null) ...[
                        const SizedBox(height: 24),
                        _buildQrCard(),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
