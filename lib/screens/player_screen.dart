import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../core/models.dart';
import '../core/scope.dart';

String _fmt(Duration d) {
  String t(int n) => n.toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${t(d.inMinutes % 60)}:${t(d.inSeconds % 60)}'
      : '${t(d.inMinutes)}:${t(d.inSeconds % 60)}';
}

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _trackName(String id, String? title, String? lang) {
  if (id == 'auto') return 'Auto';
  if (id == 'no') return 'Désactivés';
  final n = [title, lang].where((e) => e != null && e.isNotEmpty).join(' · ');
  return n.isEmpty ? 'Piste $id' : n;
}

String _vLabel(VideoTrack t) {
  if ((t.h ?? 0) > 0) return '${t.h}p';
  if (t.bitrate != null) return '${(t.bitrate! / 1000).round()} kbps';
  return 'Piste ${t.id}';
}

class PlayerScreen extends StatefulWidget {
  final List<Item>? channels;
  final int index;
  final String? url;
  final String title;
  final Item? item;

  const PlayerScreen.live({super.key, required this.channels, this.index = 0})
      : url = null,
        title = '',
        item = null;

  const PlayerScreen.vod({
    super.key,
    required this.url,
    required this.title,
    required this.item,
  })  : channels = null,
        index = 0;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _fits = [BoxFit.contain, BoxFit.cover, BoxFit.fill];
  static const _panelW = 290.0;

  late final AppScope app;
  late final Player player;
  late final VideoController controller;
  final _subs = <StreamSubscription>[];
  final _focus = FocusNode();
  final _playFocus = FocusNode();
  final _panelFocus = FocusNode();
  Timer? _hide, _save, _info, _abr, _digitTimer;

  late int _idx;
  late int _fit;
  int? _prevIdx;
  int _gen = 0;
  bool _show = false, _showInfo = false, _buffering = true;
  bool _panel = false, _chanList = false, _started = false;
  String? _error;
  List<Programme> _progs = [];
  int _retries = 0;
  String _digits = '';
  double _rate = 1.0;

  // qualité adaptative
  String _q = 'auto';
  int? _vIdx;
  final _stalls = <DateTime>[];
  DateTime _lastChange = DateTime.now();

  bool get _live => widget.channels != null;
  Item get _item => _live ? widget.channels![_idx] : widget.item!;
  String get _title => _live ? _item.name : widget.title;
  int get _step => app.store.get<int>('seek_step', 10);

  List<VideoTrack> get _variants {
    final l = player.state.tracks.video
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList()
      ..sort((a, b) => (a.h ?? 0).compareTo(b.h ?? 0));
    return l;
  }

  @override
  void initState() {
    super.initState();
    app = AppScope.of(context);
    final st = app.store;
    _idx = widget.index;
    _fit = st.get<int>('fit', 0);

    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    const sizes = [8, 32, 64];
    player = Player(
        configuration:
            PlayerConfiguration(bufferSize: sizes[st.get<int>('buffer', 1)] * 1024 * 1024));
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: st.get<bool>('hwdec', true)),
    );

    if (!kIsWeb && _live && st.get<bool>('fast_zap', true)) {
      try {
        final p = player.platform;
          final dynamic dyn = p;
        dyn.setProperty('reconnect', '1');
        dyn.setProperty('reconnect-streamed', '1');
        dyn.setProperty('reconnect-delay-max', '5');
        dyn.setProperty('network-timeout', '15');
        dyn.setProperty('demuxer-readahead-secs', '4');

      } catch (_) {}
    }

    _subs.addAll([
      player.stream.error.listen(_onError),
      player.stream.buffering.listen((b) {
        if (b && _started) _stalls.add(DateTime.now());
        if (mounted) setState(() => _buffering = b);
      }),
      player.stream.playing.listen((p) {
        if (p) {
          _retries = 0;
          _started = true;
        }
      }),
      player.stream.tracks.listen((_) {
        if (mounted && _panel) setState(() {});
      }),
    ]);
    _save = Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());
    _abr = Timer.periodic(const Duration(seconds: 15), (_) => _abrTick());
    _openCurrent();
  }

  // ---------- lecture ----------
  Future<void> _openCurrent() async {
    final st = app.store;
    final gen = ++_gen;
    String url;
    Duration? start;
    _q = 'auto';
    _vIdx = null;
    _started = false;
    _stalls.clear();
    _lastChange = DateTime.now();
    if (_live) {
      final ch = _item;
      try {
        url = await app.api.liveStream(ch, ext: st.get<String>('live_ext', 'm3u8'));
      } catch (e) {
        if (mounted && gen == _gen) setState(() => _error = '$e');
        return;
      }
      if (!mounted || gen != _gen) return;
      st.saveHistory(ch, url, ch.name, 0, 0);
      _loadEpg(ch);
    } else {
      url = widget.url!;
      if (st.get<bool>('resume', true)) {
        final e = st.entryFor(_item);
        if (e != null && e.url == url && e.pos > 15000 && e.dur - e.pos > 30000) {
          start = Duration(milliseconds: e.pos);
        }
      }
    }
    if (mounted) {
      setState(() {
        _error = null;
        _buffering = true;
      });
    }
        await player.open(Media(url, start: start, httpHeaders: const {'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18'}));

  }

  void _onError(String e) {
    if (!mounted) return;
    if (_retries < 3) {
      _retries++;
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _openCurrent();
      });
    } else {
      setState(() => _error = e);
    }
  }

  Future<void> _loadEpg(Item ch) async {
    final l = await app.epg.forChannel(ch, limit: 4);
    if (!mounted || ch.id != _item.id) return;
    setState(() => _progs = l);
  }

  void _saveProgress() {
    if (_live) return;
    final pos = player.state.position.inMilliseconds;
    final dur = player.state.duration.inMilliseconds;
    if (dur > 0 && pos > 0) {
      app.store.saveHistory(_item, widget.url!, widget.title, pos, dur);
    }
  }

  // ---------- qualité adaptative ----------
  void _abrTick() {
    if (!mounted || _q != 'auto' || !app.store.get<bool>('abr', true)) return;
    final v = _variants;
    if (v.length < 2) return;
    final now = DateTime.now();
    _stalls.removeWhere((t) => now.difference(t).inSeconds > 60);
    final cur = _vIdx ?? v.length - 1;
    if (_stalls.length >= 2 && cur > 0) {
      _vIdx = cur - 1;
      player.setVideoTrack(v[_vIdx!]);
      _stalls.clear();
      _lastChange = now;
      if (mounted) setState(() {});
    } else if (_vIdx != null &&
        _stalls.isEmpty &&
        now.difference(_lastChange).inSeconds > 90) {
      if (_vIdx! + 1 >= v.length - 1) {
        _vIdx = null;
        player.setVideoTrack(VideoTrack.auto());
      } else {
        _vIdx = _vIdx! + 1;
        player.setVideoTrack(v[_vIdx!]);
      }
      _lastChange = now;
      if (mounted) setState(() {});
    }
  }

  void _setQuality(String id) {
    _q = id;
    _stalls.clear();
    _lastChange = DateTime.now();
    if (id == 'auto') {
      _vIdx = null;
      player.setVideoTrack(VideoTrack.auto());
    } else {
      final v = _variants;
      final i = v.indexWhere((x) => x.id == id);
      if (i >= 0) {
        _vIdx = i;
        player.setVideoTrack(v[i]);
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _saveProgress();
    _hide?.cancel();
    _save?.cancel();
    _info?.cancel();
    _abr?.cancel();
    _digitTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    _focus.dispose();
    _playFocus.dispose();
    _panelFocus.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------- overlay ----------
  void _restartHide() {
    _hide?.cancel();
    if (_panel || _chanList) return;
    _hide = Timer(Duration(seconds: app.store.get<int>('overlay_secs', 6)), () {
      if (mounted) _hideOverlay();
    });
  }

  void _showOverlay() {
    setState(() => _show = true);
    _restartHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playFocus.requestFocus();
    });
  }

  void _hideOverlay() {
    _hide?.cancel();
    setState(() {
      _show = false;
      _panel = false;
      _chanList = false;
    });
    _focus.requestFocus();
  }

  void _openPanel() {
    _hide?.cancel();
    setState(() {
      _show = true;
      _panel = true;
      _chanList = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _panelFocus.requestFocus();
    });
  }

  void _togglePanel() => _panel ? setState(() => _panel = false) : _openPanel();

  void _openChanList() {
    _hide?.cancel();
    setState(() {
      _show = false;
      _panel = false;
      _chanList = true;
    });
  }

  void _flashInfo() {
    setState(() => _showInfo = true);
    _info?.cancel();
    _info = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showInfo = false);
    });
  }

  // ---------- zapping ----------
  void _jump(int i) {
    final n = widget.channels!.length;
    if (n == 0 || i == _idx) return;
    _prevIdx = _idx;
    _idx = (i % n + n) % n;
    _retries = 0;
    _progs = [];
    _flashInfo();
    _openCurrent();
  }

  void _zap(int d) => _jump(_idx + d);

  void _lastChannel() {
    if (_prevIdx != null) _jump(_prevIdx!);
  }

  void _typeDigit(String d) {
    _digits += d;
    _digitTimer?.cancel();
    _digitTimer = Timer(const Duration(milliseconds: 1800), () {
      final n = int.tryParse(_digits) ?? 0;
      _digits = '';
      final ch = widget.channels!;
      var i = ch.indexWhere((c) => c.number == n && n > 0);
      if (i < 0) i = n - 1;
      if (mounted) {
        setState(() {});
        if (i >= 0 && i < ch.length) _jump(i);
      }
    });
    setState(() {});
  }

  void _seek(int seconds) {
    var t = player.state.position + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    player.seek(t);
    _flashInfo();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    if (_show || _panel || _chanList) {
      _restartHide();
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (_live && RegExp(r'^[0-9]$').hasMatch(k.keyLabel)) {
      _typeDigit(k.keyLabel);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp) {
      _live ? _zap(-1) : _showOverlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown) {
      _live ? _zap(1) : _showOverlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) {
      _live ? _openChanList() : _seek(-_step);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) {
      _live ? _showOverlay() : _seek(_step);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.gameButtonA) {
      _showOverlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlayPause || k == LogicalKeyboardKey.space) {
      player.playOrPause();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------- UI ----------
  Widget _quick(IconData icon, String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          IconButton.filledTonal(icon: Icon(icon), onPressed: onTap),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.white70, height: 1.1)),
        ]),
      );

  Widget _topBar() => Positioned(
        top: 0,
        left: 0,
        right: _panel ? _panelW : 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 36),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_show)
              IconButton(
                icon: const Icon(Icons.arrow_back_ios),
                onPressed: () => Navigator.of(context).pop(),
              )
            else
              const SizedBox(width: 12),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PRO',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, height: 1)),
              Text('MAX TV',
                  style: TextStyle(fontSize: 11, letterSpacing: 1, color: Colors.white70)),
            ]),
            const SizedBox(width: 14),
            if (_live)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: const Color(0xFFE50914),
                    borderRadius: BorderRadius.circular(6)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 8),
                  SizedBox(width: 6),
                  Text('En Direct',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                ]),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    _live && _item.number > 0 ? '${_item.number}  $_title' : _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                if (_live && _progs.isNotEmpty)
                  Text('Maintenant : ${_progs.first.title}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                if (_live && _progs.length > 1)
                  Text('Ensuite : ${_progs[1].title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70)),
              ]),
            ),
          ]),
        ),
      );

  Widget _seekBar() => StreamBuilder<Duration>(
        stream: player.stream.position,
        initialData: player.state.position,
        builder: (_, s) {
          final pos = (s.data ?? Duration.zero).inMilliseconds.toDouble();
          final dur = player.state.duration;
          final max = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
          return Row(children: [
            Text(_fmt(s.data ?? Duration.zero),
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: pos > max ? max : pos,
                  max: max,
                  onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())),
                ),
              ),
            ),
            Text(_fmt(dur), style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]);
        },
      );

  Widget _epgBar() {
    if (_progs.isEmpty) return const SizedBox(height: 8);
    final p = _progs.first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Text(_hm(p.start), style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(width: 8),
        Expanded(child: LinearProgressIndicator(value: p.progress, minHeight: 3)),
        const SizedBox(width: 8),
        Text(_hm(p.end), style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ]),
    );
  }

  Widget _bottomBar() => Positioned(
        bottom: 0,
        left: 0,
        right: _panel ? _panelW : 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _quick(Icons.subtitles_outlined, 'Langues et\nSous-titres', _openPanel),
              _quick(Icons.hd_outlined, 'Qualité\nVidéo', _openPanel),
              _quick(Icons.settings_outlined, 'Paramètres\nAvancés', _togglePanel),
              if (_live)
                _quick(Icons.format_list_bulleted, 'Liste des\nchaînes', _openChanList),
            ]),
            const SizedBox(height: 8),
            if (_live) _epgBar() else _seekBar(),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (_live)
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  tooltip: 'Chaîne précédente',
                  onPressed: () {
                    _zap(-1);
                    _restartHide();
                  },
                )
              else
                IconButton(
                  icon: Icon(_step == 30 ? Icons.replay_30 : Icons.replay_10, size: 28),
                  onPressed: () {
                    _seek(-_step);
                    _restartHide();
                  },
                ),
              const SizedBox(width: 12),
              StreamBuilder<bool>(
                stream: player.stream.playing,
                initialData: player.state.playing,
                builder: (_, s) => IconButton(
                  focusNode: _playFocus,
                  iconSize: 44,
                  icon: Icon(s.data == true
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                  onPressed: () => player.playOrPause(),
                ),
              ),
              const SizedBox(width: 12),
              if (_live)
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  tooltip: 'Chaîne suivante',
                  onPressed: () {
                    _zap(1);
                    _restartHide();
                  },
                )
              else
                IconButton(
                  icon: Icon(_step == 30 ? Icons.forward_30 : Icons.forward_10, size: 28),
                  onPressed: () {
                    _seek(_step);
                    _restartHide();
                  },
                ),
              if (_live) ...[
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.swap_horiz),
                  tooltip: 'Dernière chaîne',
                  onPressed: _lastChannel,
                ),
              ],
              const SizedBox(width: 12),
              IconButton(
                icon: Icon(app.store.isFav(_item) ? Icons.favorite : Icons.favorite_border),
                tooltip: 'Favori',
                onPressed: () async {
                  await app.store.toggleFav(_item);
                  if (mounted) setState(() {});
                },
              ),
            ]),
          ]),
        ),
      );

  Widget _panelView() {
    final t = player.state.tracks;
    final cur = player.state.track;
    final v = _variants;
    Widget head(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
        child: Text(s.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: Theme.of(context).colorScheme.primary)));
    Widget opt(String label, bool sel, VoidCallback tap, {FocusNode? f}) => ListTile(
          dense: true,
          focusNode: f,
          title: Text(label),
          trailing: sel ? const Icon(Icons.check, size: 18) : null,
          onTap: tap,
        );
    final abr = app.store.get<bool>('abr', true);
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: _panelW,
      child: Material(
        color: const Color(0xF2121418),
        child: SafeArea(
          child: ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: Row(children: [
                const Text('Réglages',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _panel = false)),
              ]),
            ),
            head('Qualité vidéo'),
            opt(abr ? 'Auto (adaptatif)' : 'Auto', _q == 'auto', () => _setQuality('auto'),
                f: _panelFocus),
            for (final x in v) opt(_vLabel(x), _q == x.id, () => _setQuality(x.id)),
            if (v.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text('Une seule qualité disponible',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            head('Audio'),
            for (final a in t.audio)
              opt(_trackName(a.id, a.title, a.language), cur.audio.id == a.id, () {
                player.setAudioTrack(a);
                setState(() {});
              }),
            head('Sous-titres'),
            for (final s in t.subtitle)
              opt(_trackName(s.id, s.title, s.language), cur.subtitle.id == s.id, () {
                player.setSubtitleTrack(s);
                setState(() {});
              }),
            head("Format de l'image"),
            for (final e in const {0: 'Adapté', 1: 'Remplir', 2: 'Étirer'}.entries)
              opt(e.value, _fit == e.key, () => setState(() => _fit = e.key)),
            if (!_live) ...[
              head('Vitesse'),
              for (final r in const [0.75, 1.0, 1.25, 1.5, 2.0])
                opt('${r}x', _rate == r, () {
                  player.setRate(r);
                  setState(() => _rate = r);
                }),
            ],
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  Widget _chanListView() {
    final ch = widget.channels!;
    final ctrl = ScrollController(
        initialScrollOffset: ((_idx * 56.0) - 150).clamp(0.0, double.infinity).toDouble());
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: 300,
      child: Material(
        color: const Color(0xF2121418),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: Row(children: [
                const Text('Chaînes',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _chanList = false)),
              ]),
            ),
            Expanded(
              child: ListView.builder(
                controller: ctrl,
                itemExtent: 56,
                itemCount: ch.length,
                itemBuilder: (_, i) => ListTile(
                  autofocus: i == _idx,
                  selected: i == _idx,
                  dense: true,
                  leading: Text('${ch[i].number > 0 ? ch[i].number : i + 1}',
                      style: const TextStyle(color: Colors.white54)),
                  title: Text(ch[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    setState(() => _chanList = false);
                    _jump(i);
                    _focus.requestFocus();
                  },
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !(_show || _panel || _chanList),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _hideOverlay();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Focus(
            focusNode: _focus,
            autofocus: true,
            onKeyEvent: _onKey,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => (_show || _panel || _chanList) ? _hideOverlay() : _showOverlay(),
              child: Stack(fit: StackFit.expand, children: [
                Video(
                  controller: controller,
                  controls: NoVideoControls,
                  fit: _fits[_fit],
                ),
                if (_buffering && _error == null)
                  const Center(child: CircularProgressIndicator()),
                if (_error != null)
                  Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline, size: 40),
                      const SizedBox(height: 8),
                      const Text('Lecture impossible'),
                      Text(_error!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () {
                          _retries = 0;
                          _openCurrent();
                        },
                        child: const Text('Réessayer'),
                      ),
                    ]),
                  ),
                if (_digits.isNotEmpty)
                  Positioned(
                    top: 24,
                    right: 32,
                    child: Text(_digits,
                        style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(blurRadius: 8)])),
                  ),
                if (_show || _showInfo) _topBar(),
                if (_show) _bottomBar(),
                if (_panel) _panelView(),
                if (_chanList && _live) _chanListView(),
              ]),
            ),
          ),
        ),
      );
}
