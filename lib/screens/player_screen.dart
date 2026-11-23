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

    const sizes =;
    player = Player(
        configuration: PlayerConfiguration(
            bufferSize: sizes[st.get<int>('buffer', 1)] * 1024 * 1024));
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: st.get<bool>('hwdec', true)),
    );

    if (!kIsWeb) {
      try {
        final dynamic p = player.platform;
        p.setProperty('reconnect', '1');
        p.setProperty('reconnect-streamed', '1');
        p.setProperty('reconnect-delay-max', '5');
        p.setProperty('network-timeout', '15');
        if (_live && st.get<bool>('fast_zap', true)) {
          p.setProperty('demuxer-readahead-secs', '4');
        }
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
    await player.open(
      Media(
        url,
        start: start,
        httpHeaders: const {
          'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
        },
      ),
    );
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
