import 'dart:async';
import 'dart:io' show Platform;
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../core/models.dart';
import '../core/scope.dart';
import '../data/catalog_repository.dart';

const _kNeon = Color(0xFF69F028);

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
  if (id == 'no') return 'Désactivé';
  final n = <String>[
    if (title != null && title.isNotEmpty) title,
    if (lang != null && lang.isNotEmpty) lang,
  ].join(' · ');
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
  static final _fits = List<BoxFit>.of(<BoxFit>[
    BoxFit.contain,
    BoxFit.cover,
    BoxFit.fill,
  ]);
  static const _fitNames = <String>[
    'Ajuster',
    'Zoom (plein écran)',
    'Étirer',
  ];
  static const _panelW = 310.0;

  late AppScope app;
  bool _inited = false;
  late final Player player;
  late final VideoController controller;

  final _subs = <StreamSubscription>[];
  final _focus = FocusNode();
  final _playFocus = FocusNode();
  Timer? _hide, _save, _info, _abr, _digitTimer, _zapDebounce;
  Timer? _longTimer;
  LogicalKeyboardKey? _downKey;
  bool _longHandled = false;
  
  late List<Item> _allChannels;
  List<Cat> _cats = <Cat>[];
  String _selectedCat = 'all';

  final Map<int, String> _epgNowTitles = <int, String>{};
  final Set<int> _epgLoading = <int>{};

  late int _idx;
  late int _fit;
  int? _prevIdx;
  int _gen = 0;
  bool _show = false, _showInfo = false, _buffering = true;
  bool _panel = false, _chanList = false, _started = false;
  String? _error;
  List<Programme> _progs = <Programme>[];
  int _retries = 0;
  String _digits = '';
  double _rate = 1.0;

  String _q = 'auto';
  int? _vIdx;
  final _stalls = <DateTime>[];
  DateTime _lastChange = DateTime.now();

  bool get _live => widget.channels != null;
  Item get _item => _live ? _allChannels.elementAt(_idx) : widget.item!;
  String get _title => _live ? _item.name : widget.title;
  int get _step => app.store.get<int>('seek_step', 10);
  int get _overlaySecs => app.store.get<int>('overlay_secs', 6);

  List<VideoTrack> get _variants {
    final l = player.state.tracks.video
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList()
      ..sort((a, b) => (a.h ?? 0).compareTo(b.h ?? 0));
    return l;
  }

  String get _activeResLabel {
    final h = player.state.track.video.h ?? player.state.height ?? 0;
    return h > 0 ? '${h}p' : '';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;

    app = AppScope.of(context);
    final st = app.store;
    _allChannels = _live ? List<Item>.of(widget.channels!) : <Item>[];
    _idx = widget.index;
    _fit = st.get<int>('fit', 0).clamp(0, 2);

    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    final sizes = _live ? <int>[4, 8, 16] : <int>[16, 32, 48];
    final bufIdx = st.get<int>('buffer', 1).clamp(0, 2);
    final useHw = st.get<bool>('hwdec', false);

    player = Player(
      configuration: PlayerConfiguration(
        bufferSize: sizes.elementAt(bufIdx) * 1024 * 1024,
      ),
    );
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: useHw,
      ),
    );

    if (!kIsWeb) {
      try {
        final dynamic dyn = player.platform;
        dyn.setProperty('hwdec', useHw ? 'auto-safe' : 'no');
        dyn.setProperty('reconnect', '1');
        dyn.setProperty('reconnect-streamed', '1');
        dyn.setProperty('reconnect-delay-max', '2');
        dyn.setProperty('network-timeout', '8');
        dyn.setProperty('tls-verify', 'no');
        dyn.setProperty('hls-bitrate', 'max');
        dyn.setProperty('demuxer-max-back-bytes', '10MiB');

        if (_live) {
          dyn.setProperty('cache', 'yes');
          dyn.setProperty('cache-pause', 'no');
          dyn.setProperty('demuxer-readahead-secs', '1.5');
          dyn.setProperty('demuxer-max-bytes', '${sizes.elementAt(bufIdx)}MiB');
          dyn.setProperty('demuxer-lavf-probesize', '500000');
          dyn.setProperty('demuxer-lavf-analyzeduration', '0.5');
          dyn.setProperty('video-sync', 'audio');
          dyn.setProperty('framedrop', 'vo');
        } else {
          dyn.setProperty('demuxer-readahead-secs', '6');
        }
      } catch (_) {}
    }

    _subs.addAll(<StreamSubscription>[
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
      player.stream.track.listen((_) {
        if (mounted && _panel) setState(() {});
      }),
    ]);

    _save = Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());
    _abr = Timer.periodic(const Duration(seconds: 15), (_) => _abrTick());
    if (_live) _loadFolders();
    _openCurrent();
    HardwareKeyboard.instance.addHandler(_onRawKey);
  }

  Future<void> _loadFolders() async {
    try {
      final c = await app.repo.categories(Kind.live);
      final all = await app.repo.items(Kind.live);
      if (!mounted) return;
      final cur = _item;
      setState(() {
        _cats = <Cat>[const Cat('all', 'Toutes les chaînes'), ...c];
        if (all.isNotEmpty) {
          _allChannels = all;
          final found = all.indexWhere((x) => x.id == cur.id);
          if (found >= 0) _idx = found;
        }
        if (_item.cat.isNotEmpty) _selectedCat = _item.cat;
      });
    } catch (_) {}
  }

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

    if (mounted) {
      setState(() {
        _error = null;
        _buffering = true;
      });
    }

    if (_live) {
      final ch = _item;
      try {
        url = await app.api.liveStream(ch, ext: st.get<String>('live_ext', 'm3u8'));
      } catch (e) {
        if (mounted && gen == _gen) setState(() => _error = '$e');
        return;
      }
      if (!mounted || gen != _gen) return;

      unawaited(st.saveHistory(ch, url, ch.name, 0, 0));
      unawaited(_loadEpg(ch));
    } else {
      url = widget.url!;
      if (st.get<bool>('resume', true)) {
        final e = st.entryFor(_item);
        if (e != null && e.url == url && e.pos > 15000 && e.dur - e.pos > 30000) {
          start = Duration(milliseconds: e.pos);
        }
      }
    }

    if (!mounted || gen != _gen) return;

    if (st.get<String>('default_player', 'internal') == 'external') {
      await _openExternalPlayer(url);
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }

    await player.open(
      Media(
        url,
        start: start,
        httpHeaders: const <String, String>{
          'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
          'Connection': 'keep-alive',
        },
      ),
      play: true,
    );
  }

  void _onError(String e) {
    if (!mounted) return;
    if (_retries < 3) {
      _retries++;
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) _openCurrent();
      });
    } else {
      setState(() => _error = e);
    }
  }

  Future<void> _loadEpg(Item ch) async {
    try {
      final l = await app.epg.forChannel(ch, limit: 4);
      if (!mounted) return;
      if (l.isNotEmpty) {
        _epgNowTitles[ch.id] = l.first.title;
      }
      if (ch.id == _item.id) {
        setState(() => _progs = l);
      }
    } catch (_) {}
  }

  void _ensureRowEpg(Item ch) {
    if (_epgNowTitles.containsKey(ch.id) || _epgLoading.contains(ch.id)) return;
    _epgLoading.add(ch.id);
    app.epg.forChannel(ch, limit: 1).then((l) {
      _epgLoading.remove(ch.id);
      if (!mounted) return;
      setState(() {
        _epgNowTitles[ch.id] = l.isNotEmpty ? l.first.title : '';
      });
    }).catchError((_) {
      _epgLoading.remove(ch.id);
    });
  }

  void _saveProgress() {
    if (_live) return;
    final pos = player.state.position.inMilliseconds;
    final dur = player.state.duration.inMilliseconds;
    if (dur > 0 && pos > 0) {
      app.store.saveHistory(_item, widget.url!, widget.title, pos, dur);
    }
  }

    void _abrTick() {
    if (!mounted || _q != 'auto' || !app.store.get<bool>('abr', true)) return;
    final v = _variants;
    if (v.length < 2) return;
    final now = DateTime.now();
    _stalls.removeWhere((t) => now.difference(t).inSeconds > 60);
    final cur = _vIdx ?? v.length - 1;
    if (_stalls.length >= 2 && cur > 0) {
      _vIdx = cur - 1;
      player.setVideoTrack(v.elementAt(_vIdx!));
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
        player.setVideoTrack(v.elementAt(_vIdx!));
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
        player.setVideoTrack(v.elementAt(i));
      }
    }
    setState(() {});
  }

  Future<void> _openExternalPlayer([String? forcedUrl]) async {
    if (kIsWeb || !Platform.isAndroid) return;

    final currentUrl = forcedUrl ??
        (player.state.playlist.medias.isNotEmpty
            ? player.state.playlist.medias.first.uri
            : (_live
                ? await app.api.liveStream(
                    _item,
                    ext: app.store.get<String>('live_ext', 'm3u8'),
                  )
                : widget.url));

    if (currentUrl == null || currentUrl.isEmpty) return;

    await player.pause();
    final intent = AndroidIntent(
      action: 'action_view',
      data: currentUrl,
      type: 'video/*',
    );
    await intent.launch();
  }

  void _zap(int delta) {
    if (!_live || _allChannels.isEmpty) return;
    _prevIdx = _idx;
    setState(() {
      _idx = (_idx + delta) % _allChannels.length;
      if (_idx < 0) _idx += _allChannels.length;
      _digits = '';
    });
    _showBanner();
    _zapDebounce?.cancel();
    _zapDebounce = Timer(const Duration(milliseconds: 280), _openCurrent);
  }

  void _jumpToIndex(int newIdx) {
    if (!_live || newIdx < 0 || newIdx >= _allChannels.length) return;
    if (newIdx == _idx) return;
    _prevIdx = _idx;
    setState(() {
      _idx = newIdx;
      _chanList = false;
      _digits = '';
    });
    _showBanner();
    _openCurrent();
  }

  void _shiftCategory(int delta) {
    if (_cats.isEmpty) return;
    final i = _cats.indexWhere((c) => c.id == _selectedCat);
    final next = ((i < 0 ? 0 : i) + delta + _cats.length) % _cats.length;
    setState(() => _selectedCat = _cats[next].id);
  }

  void _onDigit(String d) {
    if (!_live) return;
    setState(() {
      if (_digits.length >= 4) _digits = '';
      _digits += d;
    });
    _digitTimer?.cancel();
    _digitTimer = Timer(const Duration(milliseconds: 1400), () {
      final num = int.tryParse(_digits);
      if (mounted) setState(() => _digits = '');
      if (num != null && num >= 1 && num <= _allChannels.length) {
        _jumpToIndex(num - 1);
      }
    });
  }

  void _showBanner() {
    setState(() => _showInfo = true);
    _info?.cancel();
    _info = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showInfo = false);
    });
  }

  void _toggleControls([bool? force]) {
    final next = force ?? !_show;
    setState(() => _show = next);
    _hide?.cancel();
    if (next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_panel && !_chanList) _playFocus.requestFocus();
      });
      _hide = Timer(Duration(seconds: _overlaySecs), () {
        if (mounted && !_panel && !_chanList) setState(() => _show = false);
      });
    } else {
      _focus.requestFocus();
    }
  }

  void _bumpControls() {
    if (!_show) return;
    _hide?.cancel();
    _hide = Timer(Duration(seconds: _overlaySecs), () {
      if (mounted && !_panel && !_chanList) setState(() => _show = false);
    });
  }

  void _setFit(int idx) {
    setState(() => _fit = idx.clamp(0, _fits.length - 1));
    app.store.set('fit', _fit);
  }

  void _cycleRate() {
    const rates = <double>[1.0, 1.25, 1.5, 2.0];
    final next = rates[(rates.indexOf(_rate) + 1) % rates.length];
    setState(() => _rate = next);
    player.setRate(next);
  }

  void _seekBy(int seconds) {
    if (_live) return;
    final dur = player.state.duration;
    if (dur <= Duration.zero) return;
    final target = player.state.position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > dur ? dur : target);
    player.seek(clamped);
    _bumpControls();
  }

    void _runRemoteAction(String action) {
    switch (action) {
      case 'channel_list':
        if (_live) setState(() => _chanList = true);
        break;
      case 'channel_up':
        if (_live) _zap(1);
        break;
      case 'channel_down':
        if (_live) _zap(-1);
        break;
      case 'seek_back':
        if (!_live) {
          _seekBy(-_step);
          _toggleControls(true);
        } else if (_prevIdx != null) {
          _jumpToIndex(_prevIdx!);
        }
        break;
      case 'seek_forward':
        if (!_live) {
          _seekBy(_step);
          _toggleControls(true);
        }
        break;
      case 'toggle_controls':
        _toggleControls(true);
        break;
      case 'epg_guide':
        _showBanner();
        break;
               case 'toggle_fav':
        setState(() => _panel = true);
        break;

    }
  }

  String? _keyPrefix(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      return 'rc_ok';
    }
    if (key == LogicalKeyboardKey.arrowLeft) return 'rc_left';
    if (key == LogicalKeyboardKey.arrowRight) return 'rc_right';
    if (key == LogicalKeyboardKey.arrowUp) return 'rc_up';
    if (key == LogicalKeyboardKey.arrowDown) return 'rc_down';
    return null;
  }

  bool _onRawKey(KeyEvent event) {
    if (!mounted) return false;
    final key = event.logicalKey;

    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack ||
          key == LogicalKeyboardKey.browserBack) {
        if (_panel || _chanList) {
          setState(() {
            _panel = false;
            _chanList = false;
          });
          _focus.requestFocus();
          return true;
        }
        if (_show) {
          _toggleControls(false);
          return true;
        }
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        return true;
      }

      if (_chanList) {
        if (key == LogicalKeyboardKey.arrowLeft) {
          _shiftCategory(-1);
          return true;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          _shiftCategory(1);
          return true;
        }
        return false;
      }

      if (_panel) return false;

      if (_show) {
        _bumpControls();
        return false;
      }

      if (key == LogicalKeyboardKey.channelUp && _live) {
        _zap(1);
        return true;
      }
      if (key == LogicalKeyboardKey.channelDown && _live) {
        _zap(-1);
        return true;
      }

      final prefix = _keyPrefix(key);
      if (prefix != null) {
        _downKey = key;
        _longHandled = false;
        _longTimer?.cancel();
        _longTimer = Timer(const Duration(milliseconds: 500), () {
          if (!mounted || _downKey != key) return;
          _longHandled = true;
          final longAct = app.store.get<String>('${prefix}_long', 'none');
          if (longAct != 'none') _runRemoteAction(longAct);
        });
        return true;
      }
    } else if (event is KeyUpEvent) {
      final prefix = _keyPrefix(key);
      if (prefix != null && _downKey == key) {
        _longTimer?.cancel();
        _downKey = null;
        if (!_longHandled) {
          final defAct = prefix == 'rc_ok'
              ? 'toggle_controls'
              : prefix == 'rc_left'
                  ? 'seek_back'
                  : prefix == 'rc_right'
                      ? 'seek_forward'
                      : prefix == 'rc_up'
                          ? 'channel_up'
                          : 'channel_down';
          final act = app.store.get<String>(prefix, defAct);
          if (act != 'none') _runRemoteAction(act);
        }
        _longHandled = false;
        return true;
      }
    }

    return false;
  }
   
    

    
  

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (_panel || _chanList) return KeyEventResult.ignored;

    final digitMap = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.digit0: '0',
      LogicalKeyboardKey.numpad0: '0',
      LogicalKeyboardKey.digit1: '1',
      LogicalKeyboardKey.numpad1: '1',
      LogicalKeyboardKey.digit2: '2',
      LogicalKeyboardKey.numpad2: '2',
      LogicalKeyboardKey.digit3: '3',
      LogicalKeyboardKey.numpad3: '3',
      LogicalKeyboardKey.digit4: '4',
      LogicalKeyboardKey.numpad4: '4',
      LogicalKeyboardKey.digit5: '5',
      LogicalKeyboardKey.numpad5: '5',
      LogicalKeyboardKey.digit6: '6',
      LogicalKeyboardKey.numpad6: '6',
      LogicalKeyboardKey.digit7: '7',
      LogicalKeyboardKey.numpad7: '7',
      LogicalKeyboardKey.digit8: '8',
      LogicalKeyboardKey.numpad8: '8',
      LogicalKeyboardKey.digit9: '9',
      LogicalKeyboardKey.numpad9: '9',
    };
    if (digitMap.containsKey(key)) {
      _onDigit(digitMap[key]!);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.space) {
      player.playOrPause();
      _toggleControls(true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.info) {
      _showBanner();
      return KeyEventResult.handled;
    }

    if (_show) _bumpControls();
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    if (_inited) {
      HardwareKeyboard.instance.removeHandler(_onRawKey);
      _saveProgress();
      player.dispose();
    }
    for (final s in _subs) {
      s.cancel();
    }
    _hide?.cancel();
    _save?.cancel();
    _info?.cancel();
    _abr?.cancel();
    _digitTimer?.cancel();
    _zapDebounce?.cancel();
    _longTimer?.cancel();
    
    _focus.dispose();
    _playFocus.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_panel || _chanList) {
          setState(() {
            _panel = false;
            _chanList = false;
          });
          _focus.requestFocus();
        } else if (_show) {
          _toggleControls(false);
        } else if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_panel || _chanList) {
                setState(() {
                  _panel = false;
                  _chanList = false;
                });
                _focus.requestFocus();
              } else {
                _toggleControls();
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const ColoredBox(color: Colors.black),

                // Flux vidéo
                AnimatedOpacity(
                  opacity: _started ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: Video(
                    controller: controller,
                    fit: _fits[_fit],
                    fill: Colors.black,
                    controls: NoVideoControls,
                  ),
                ),

                // Chargement
                if (_buffering && _error == null)
                  const Center(
                    child: CircularProgressIndicator(color: _kNeon),
                  ),

                // Erreur + Réessayer / Lecteur externe
                if (_error != null)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E1420),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.error_outline,
                              color: Colors.redAccent, size: 40),
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 12,
                            alignment: WrapAlignment.center,
                            children: <Widget>[
                              FilledButton.icon(
                                autofocus: true,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _kNeon,
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: () {
                                  _retries = 0;
                                  _openCurrent();
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('Réessayer'),
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white54),
                                ),
                                onPressed: () => _openExternalPlayer(),
                                icon: const Icon(Icons.open_in_new),
                                label: const Text('Lecteur externe'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                // Numéro saisi à la télécommande
                if (_digits.isNotEmpty)
                  Positioned(
                    top: 28,
                    right: 32,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kNeon, width: 2),
                      ),
                      child: Text(
                        _digits,
                        style: const TextStyle(
                          color: _kNeon,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // Bannière info zapping / EPG
                if (_live && (_showInfo || _show) && !_chanList)
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: _show ? 88 : 24,
                    child: _buildLiveHeader(),
                  ),

                // Barre de contrôle en bas
                if (_show && !_chanList)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildBottomControls(),
                  ),

                // Tiroir latéral gauche : Liste compacte (Numéro + Logo + Nom + EPG)
                if (_live && _chanList)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 390,
                    child: _buildChannelDrawer(),
                  ),

                // Panneau latéral droit : Audio, Sous-titres, Qualité & Format
                if (_panel)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: _panelW,
                    child: _buildTracksPanel(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- BANNIÈRE INFO CHAÎNE + EPG ---
  Widget _buildLiveHeader() {
    final nowProg = _progs.isNotEmpty ? _progs.first : null;
        final nextProg = _progs.length > 1 ? _progs.elementAt(1) : null;

    double progress = 0.0;
    if (nowProg != null) {
      final total = nowProg.end.difference(nowProg.start).inSeconds;
      final elapsed = DateTime.now().difference(nowProg.start).inSeconds;
      if (total > 0) progress = (elapsed / total).clamp(0.0, 1.0);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xE60B101C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _kNeon,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${_idx + 1}',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (nowProg != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Text(
                        '${_hm(nowProg.start)} - ${_hm(nowProg.end)}',
                        style: const TextStyle(color: _kNeon, fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          nowProg.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(_kNeon),
                    ),
                  ),
                  if (nextProg != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      'À suivre (${_hm(nextProg.start)}) : ${nextProg.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- BARRE DE CONTRÔLE EN BAS ---
  Widget _buildBottomControls() {
    final isFav = app.store.isFav(_item);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[Color(0xF2070B14), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!_live)
            StreamBuilder<Duration>(
              stream: player.stream.position,
              builder: (_, snap) {
                final pos = snap.data ?? player.state.position;
                final dur = player.state.duration;
                final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
                final valMs = pos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
                return Row(
                  children: <Widget>[
                    Text(_fmt(pos), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    Expanded(
                      child: Slider(
                        activeColor: _kNeon,
                        inactiveColor: Colors.white24,
                        value: valMs,
                        max: maxMs,
                        onChanged: (v) {
                          player.seek(Duration(milliseconds: v.toInt()));
                          _bumpControls();
                        },
                      ),
                    ),
                    Text(_fmt(dur), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                );
              },
            ),
          Row(
            children: <Widget>[
              if (_live) ...<Widget>[
                _osdButton(
                  icon: Icons.list,
                  label: 'Chaînes',
                  onPressed: () {
                    setState(() {
                      _show = false;
                      _chanList = true;
                    });
                  },
                ),
                const SizedBox(width: 8),
                _osdButton(
                  icon: isFav ? Icons.star : Icons.star_border,
                  label: isFav ? 'Favori' : 'Ajouter',
                  onPressed: () async {
                    await app.store.toggleFav(_item);
                    setState(() {});
                  },
                ),
              ],
              if (!_live) ...<Widget>[
                Expanded(
                  child: Text(
                    _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                _osdButton(
                  icon: Icons.replay_10,
                  label: '-${_step}s',
                  onPressed: () => _seekBy(-_step),
                ),
              ] else
                const Spacer(),

              // Bouton Lecture / Pause central
              StreamBuilder<bool>(
                stream: player.stream.playing,
                builder: (_, snap) {
                  final playing = snap.data ?? player.state.playing;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: IconButton.filled(
                      focusNode: _playFocus,
                      style: IconButton.styleFrom(
                        backgroundColor: _kNeon,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.all(12),
                      ),
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow, size: 26),
                      onPressed: () {
                        player.playOrPause();
                        _bumpControls();
                      },
                    ),
                  );
                },
              ),

              if (!_live) ...<Widget>[
                _osdButton(
                  icon: Icons.forward_10,
                  label: '+${_step}s',
                  onPressed: () => _seekBy(_step),
                ),
                const Spacer(),
              ] else
                const Spacer(),

              _osdButton(
                icon: Icons.subtitles,
                label: 'Audio & Qualité',
                onPressed: () {
                  setState(() {
                    _show = false;
                    _panel = true;
                  });
                },
              ),
              const SizedBox(width: 8),
              if (!kIsWeb)
                _osdButton(
                  icon: Icons.open_in_new,
                  label: 'Externe',
                  onPressed: () => _openExternalPlayer(),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _osdButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white24),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) return _kNeon;
          return Colors.black54;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) return Colors.black;
          return Colors.white;
        }),
      ),
      onPressed: () {
        _bumpControls();
        onPressed();
      },
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }

  // --- TIROIR GAUCHE : LISTE COMPACTE (NUMÉRO + LOGO + NOM + EPG EN DESSOUS) ---
  Widget _buildChannelDrawer() {
    final filtered = _selectedCat == 'all'
        ? _allChannels
        : _allChannels.where((c) => c.cat == _selectedCat).toList();

    final currentCatName = _cats
        .firstWhere(
          (c) => c.id == _selectedCat,
          orElse: () => const Cat('all', 'Toutes les chaînes'),
        )
        .name;

    return Container(
      color: const Color(0xF50B0E14),
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF121722),
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: _kNeon),
                    onPressed: () => _shiftCategory(-1),
                  ),
                  Expanded(
                    child: Text(
                      currentCatName,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, color: _kNeon),
                    onPressed: () => _shiftCategory(1),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final ch = filtered[i];
                  final realIdx = _allChannels.indexWhere((x) => x.id == ch.id);
                  final selected = realIdx == _idx;
                  _ensureRowEpg(ch);
                  final epgTitle = _epgNowTitles[ch.id] ?? '';

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: InkWell(
                      autofocus: selected,
                      borderRadius: BorderRadius.circular(10),
                      focusColor: _kNeon.withOpacity(0.28),
                      onTap: () => _jumpToIndex(realIdx),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? _kNeon.withOpacity(0.18)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: selected
                              ? Border.all(color: _kNeon, width: 1.2)
                              : null,
                        ),
                        child: Row(
                          children: <Widget>[
                              SizedBox(
                              width: 38,
                              child: Text(
                                '${realIdx + 1}',
                                style: TextStyle(
                                  color: selected ? _kNeon : Colors.white54,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.tv,
                              color: Colors.white38,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    ch.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: selected ? _kNeon : Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  if (epgTitle.isNotEmpty) ...<Widget>[
                                    const SizedBox(height: 2),
                                    Text(
                                      epgTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white70
                                            : Colors.white54,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- PANNEAU DROIT : AUDIO, SOUS-TITRES, QUALITÉ & FORMAT ---
  Widget _buildTracksPanel() {
    final audios = player.state.tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    final subs = player.state.tracks.subtitle
        .where((t) => t.id != 'auto')
        .toList();
    final curAudio = player.state.track.audio.id;
    final curSub = player.state.track.subtitle.id;
    final res = _activeResLabel;

    Widget sectionTitle(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Text(
            t.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        );

    Widget radioRow(String label, bool selected, VoidCallback onTap,
        {bool autofocus = false}) {
      return ListTile(
        autofocus: autofocus,
        dense: true,
        title: Text(
          label,
          style: TextStyle(
            color: selected ? _kNeon : Colors.white,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        trailing: selected
            ? const Icon(Icons.check, color: _kNeon, size: 18)
            : null,
        onTap: onTap,
      );
    }

    return Container(
      color: const Color(0xF5111726),
      child: SafeArea(
        child: ListView(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Audio et sous-titres',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            sectionTitle(_live ? 'Direct TV' : 'Lecture'),
            ListTile(
              autofocus: true,
              dense: true,
              leading: const Icon(Icons.pause_circle_outline, color: Colors.white70),
              title: const Text('Mettre en pause / Reprendre',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                player.playOrPause();
                setState(() => _panel = false);
              },
            ),
            if (!kIsWeb)
              ListTile(
                dense: true,
                leading: const Icon(Icons.open_in_new, color: _kNeon),
                title: const Text('Ouvrir dans VLC / MX Player',
                    style: TextStyle(color: _kNeon, fontSize: 14)),
                onTap: () {
                  setState(() => _panel = false);
                  _openExternalPlayer();
                },
              ),

            sectionTitle('Sous-titres'),
            radioRow('Désactivé', curSub == 'no', () {
              player.setSubtitleTrack(SubtitleTrack.no());
              setState(() {});
            }),
            for (final s in subs)
              if (s.id != 'no')
                radioRow(_trackName(s.id, s.title, s.language), curSub == s.id, () {
                  player.setSubtitleTrack(s);
                  setState(() {});
                }),

            sectionTitle('Audio'),
            if (audios.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text('Piste par défaut',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              )
            else
              for (final a in audios)
                radioRow(_trackName(a.id, a.title, a.language), curAudio == a.id, () {
                  player.setAudioTrack(a);
                  setState(() {});
                }),

            sectionTitle('Qualité'),
            radioRow(
              res.isNotEmpty ? 'Auto (now $res)' : 'Auto',
              _q == 'auto',
              () => _setQuality('auto'),
            ),
            for (final v in _variants)
              radioRow(_vLabel(v), _q == v.id, () => _setQuality(v.id)),

            sectionTitle('Format de l\'image'),
            for (int i = 0; i < _fitNames.length; i++)
              radioRow(_fitNames[i], _fit == i, () => _setFit(i)),

            if (!_live) ...<Widget>[
              sectionTitle('Vitesse'),
              ListTile(
                dense: true,
                title: Text('Vitesse : ${_rate}x',
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                onTap: _cycleRate,
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}


