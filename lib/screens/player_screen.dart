import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../core/models.dart';
import '../core/scope.dart';

String _b64(dynamic v) {
  final s = v == null ? '' : '$v';
  try {
    return utf8.decode(base64.decode(s));
  } catch (_) {
    return s;
  }
}

String _fmt(Duration d) {
  String t(int n) => n.toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${t(d.inMinutes % 60)}:${t(d.inSeconds % 60)}'
      : '${t(d.inMinutes)}:${t(d.inSeconds % 60)}';
}

String _trackName(String id, String? title, String? lang) {
  if (id == 'auto') return 'Auto';
  if (id == 'no') return 'Désactivés';
  final n = [title, lang].where((e) => e != null && e.isNotEmpty).join(' · ');
  return n.isEmpty ? 'Piste $id' : n;
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

  late final AppScope app;
  late final Player player;
  late final VideoController controller;
  final _subs = <StreamSubscription>[];
  final _focus = FocusNode();
  final _playFocus = FocusNode();
  Timer? _hide, _save, _info;
  late int _idx;
  late int _fit;
  bool _show = false, _showInfo = false, _buffering = true;
  String? _error;
  String _now = '', _next = '';
  int _retries = 0;

  bool get _live => widget.channels != null;
  Item get _item => _live ? widget.channels![_idx] : widget.item!;
  String get _title => _live ? _item.name : widget.title;

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
    final buf = sizes[st.get<int>('buffer', 1)] * 1024 * 1024;
    player = Player(configuration: PlayerConfiguration(bufferSize: buf));
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: st.get<bool>('hwdec', true)),
    );

    _subs.addAll([
      player.stream.error.listen(_onError),
      player.stream.buffering.listen((b) {
        if (mounted) setState(() => _buffering = b);
      }),
      player.stream.playing.listen((p) {
        if (p) _retries = 0;
      }),
    ]);
    _save = Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());
    _openCurrent();
  }

  Future<void> _openCurrent() async {
    final st = app.store;
    String url;
    Duration? start;
    if (_live) {
      final ch = _item;
      url = app.api.liveUrl(ch.id, ext: st.get<String>('live_ext', 'm3u8'));
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
    await player.open(Media(url, start: start));
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
    try {
      final l = await app.api.getShortEpg(ch.id, limit: 2);
      if (!mounted || ch.id != _item.id) return;
      setState(() {
        _now = l.isNotEmpty ? _b64(l[0]['title']) : '';
        _next = l.length > 1 ? _b64(l[1]['title']) : '';
      });
    } catch (_) {}
  }

  void _saveProgress() {
    if (_live) return;
    final pos = player.state.position.inMilliseconds;
    final dur = player.state.duration.inMilliseconds;
    if (dur > 0 && pos > 0) {
      app.store.saveHistory(_item, widget.url!, widget.title, pos, dur);
    }
  }

  @override
  void dispose() {
    _saveProgress();
    _hide?.cancel();
    _save?.cancel();
    _info?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    _focus.dispose();
    _playFocus.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------- overlay ----------
  void _restartHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 6), () {
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
    if (_show) setState(() => _show = false);
    _focus.requestFocus();
  }

  void _flashInfo() {
    setState(() => _showInfo = true);
    _info?.cancel();
    _info = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showInfo = false);
    });
  }

  void _zap(int d) {
    final n = widget.channels!.length;
    if (n < 2) return;
    _idx = (_idx + d + n) % n;
    _retries = 0;
    _now = '';
    _next = '';
    _flashInfo();
    _openCurrent();
  }

  void _seek(int seconds) {
    var t = player.state.position + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    player.seek(t);
    _flashInfo();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    if (_show) {
      _restartHide();
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp) {
      _live ? _zap(-1) : _showOverlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown) {
      _live ? _zap(1) : _showOverlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) {
      _live ? _showOverlay() : _seek(-10);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) {
      _live ? _showOverlay() : _seek(10);
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

  void _tracks() {
    _restartHide();
    Widget head(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)));
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14161C),
      builder: (ctx) {
        final t = player.state.tracks;
        final cur = player.state.track;
        return SafeArea(
          child: ListView(children: [
            head('Audio'),
            for (final a in t.audio)
              ListTile(
                title: Text(_trackName(a.id, a.title, a.language)),
                trailing: cur.audio.id == a.id ? const Icon(Icons.check) : null,
                onTap: () {
                  player.setAudioTrack(a);
                  Navigator.pop(ctx);
                },
              ),
            head('Sous-titres'),
            for (final s in t.subtitle)
              ListTile(
                title: Text(_trackName(s.id, s.title, s.language)),
                trailing: cur.subtitle.id == s.id ? const Icon(Icons.check) : null,
                onTap: () {
                  player.setSubtitleTrack(s);
                  Navigator.pop(ctx);
                },
              ),
          ]),
        );
      },
    );
  }

  // ---------- UI ----------
  Widget _topBar() => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 28),
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
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            else
              const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (_live && _now.isNotEmpty)
                    Text('Maintenant : $_now',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (_live && _next.isNotEmpty)
                    Text('Ensuite : $_next',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70)),
                  if (!_live)
                    StreamBuilder<Duration>(
                      stream: player.stream.position,
                      initialData: player.state.position,
                      builder: (_, s) => Text(
                          '${_fmt(s.data ?? Duration.zero)} / ${_fmt(player.state.duration)}',
                          style: const TextStyle(color: Colors.white70)),
                    ),
                ]),
              ),
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
            Text(_fmt(s.data ?? Duration.zero)),
            Expanded(
              child: Slider(
                value: pos > max ? max : pos,
                max: max,
                onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())),
              ),
            ),
            Text(_fmt(dur)),
          ]);
        },
      );

  Widget _bottomBar() => Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!_live) _seekBar(),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (_live)
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  tooltip: 'Chaîne précédente',
                  onPressed: () {
                    _zap(-1);
                    _restartHide();
                  },
                ),
              StreamBuilder<bool>(
                stream: player.stream.playing,
                initialData: player.state.playing,
                builder: (_, s) => IconButton(
                  focusNode: _playFocus,
                  iconSize: 44,
                  icon: Icon(s.data == true ? Icons.pause_circle : Icons.play_circle),
                  onPressed: () => player.playOrPause(),
                ),
              ),
              if (_live)
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  tooltip: 'Chaîne suivante',
                  onPressed: () {
                    _zap(1);
                    _restartHide();
                  },
                ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.aspect_ratio),
                tooltip: 'Format de l\'image',
                onPressed: () {
                  setState(() => _fit = (_fit + 1) % 3);
                  _restartHide();
                },
              ),
              IconButton(
                icon: const Icon(Icons.subtitles),
                tooltip: 'Audio et sous-titres',
                onPressed: _tracks,
              ),
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

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_show,
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
              onTap: () => _show ? _hideOverlay() : _showOverlay(),
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
                if (_show || _showInfo) _topBar(),
                if (_show) _bottomBar(),
              ]),
            ),
          ),
        ),
      );
}
