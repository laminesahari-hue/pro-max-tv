import 'dart:io' show Platform;
import 'package:android_intent_plus/android_intent.dart';

import 'dart:async';
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
  if (id == 'no') return 'Désactivés';
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
  static final _fits = List<BoxFit>.of(<BoxFit>[BoxFit.contain, BoxFit.cover, BoxFit.fill]);
  static const _panelW = 290.0;

  late final AppScope app;
  late final Player player;
  late final VideoController controller;
  final _subs = <StreamSubscription>[];
  final _focus = FocusNode();
  final _playFocus = FocusNode();
  final _panelFocus = FocusNode();
  Timer? _hide, _save, _info, _abr, _digitTimer, _zapDebounce;

  late List<Item> _allChannels;
  List<Cat> _cats = <Cat>[];
  String _selectedCat = 'all';

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
    _allChannels = _live ? List<Item>.of(widget.channels!) : <Item>[];
    _idx = widget.index;
    _fit = st.get<int>('fit', 0);

    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Tampon léger en Live TV (8 Mo) pour un démarrage immédiat, plus grand en VOD
    final sizes = _live ? <int>[4, 8, 16] : <int>[16, 32, 48];
    final bufIdx = st.get<int>('buffer', 1).clamp(0, 2);

    player = Player(
      configuration: PlayerConfiguration(
        bufferSize: sizes.elementAt(bufIdx) * 1024 * 1024,
      ),
    );
        controller = VideoController(
   player,
   configuration: const VideoControllerConfiguration(
     enableHardwareAcceleration: false,
   ),
 );

 if (!kIsWeb) {
   try {
     final dynamic dyn = player.platform;
     // Décodage logiciel FFmpeg (corrige l'écran gris/rayé sur Android TV)
     dyn.setProperty('hwdec', 'no');

        // Optimisation réseau & reconnexion rapide
                dyn.setProperty('reconnect', '1');
        dyn.setProperty('reconnect-streamed', '1');
        dyn.setProperty('reconnect-delay-max', '2');
        dyn.setProperty('network-timeout', '8');
        dyn.setProperty('tls-verify', 'no');
        dyn.setProperty('hls-bitrate', 'max'); // <-- Ajoutez cette ligne (ABR natif rapide)
        dyn.setProperty('demuxer-max-back-bytes', '10MiB'); // <-- Ajoutez cette ligne


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

      // Sauvegarde historique et chargement EPG en parallèle sans bloquer la vidéo
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
      if (!mounted || ch.id != _item.id) return;
      setState(() => _progs = l);
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
                }
    setState(() {});
  }

  Future<void> _openExternalPlayer() async {
    if (kIsWeb || !Platform.isAndroid) return;

    final currentUrl = player.state.playlist.medias.isNotEmpty
        ? player.state.playlist.medias.first.uri
        : (_live
            ? await app.api.liveStream(_item, ext: app.store.get<String>('live_ext', 'm3u8'))
            : widget.url);

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
      _hide = Timer(const Duration(seconds: 5), () {
        if (mounted && !_panel && !_chanList) setState(() => _show = false);
      });
    } else {
      _focus.requestFocus();
    }
  }

  void _bumpControls() {
    if (!_show) return;
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 5), () {
      if (mounted && !_panel && !_chanList) setState(() => _show = false);
    });
  }

  void _cycleFit() {
    setState(() => _fit = (_fit + 1) % _fits.length);
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
    bool _onRawKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final key = event.logicalKey;

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

    if (_panel || _chanList) {
      return false;
    }

    if (_show) {
      _bumpControls();
      return false;
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (_live) {
        setState(() => _chanList = true);
      } else {
        _toggleControls(true);
      }
      return true;
    }

    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.channelUp) {
      if (_live) {
        _zap(1);
      } else {
        _toggleControls(true);
      }
      return true;
    }

    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.channelDown) {
      if (_live) {
        _zap(-1);
      } else {
        _toggleControls(true);
      }
      return true;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_live) {
        if (_prevIdx != null) _jumpToIndex(_prevIdx!);
      } else {
        _seekBy(-_step);
        _toggleControls(true);
      }
      return true;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (_live) {
        _toggleControls(true);
      } else {
        _seekBy(_step);
        _toggleControls(true);
      }
      return true;
    }

    return false;
  }


  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    // Retour télécommande
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      if (_panel || _chanList) {
        setState(() {
          _panel = false;
          _chanList = false;
        });
        _focus.requestFocus();
        return KeyEventResult.handled;
      }
      if (_show) {
        _toggleControls(false);
        return KeyEventResult.handled;
      }
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }

    // Laisser la navigation D-Pad gérer les panneaux ouverts
    if (_panel || _chanList) {
      return KeyEventResult.ignored;
    }

    // Pavé numérique (zapping direct par numéro de chaîne)
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

    // Touches multimédia dédiées
    if (key == LogicalKeyboardKey.channelUp) {
      _zap(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.channelDown) {
      _zap(-1);
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

    // Navigation quand l'OSD est masqué
    if (!_show) {
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        if (_live) {
          setState(() => _chanList = true);
        } else {
          _toggleControls(true);
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        if (_live) {
          _zap(1);
        } else {
          _toggleControls(true);
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        if (_live) {
          _zap(-1);
        } else {
          _toggleControls(true);
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (_live) {
          if (_prevIdx != null) _jumpToIndex(_prevIdx!);
        } else {
          _seekBy(-_step);
          _toggleControls(true);
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        if (_live) {
          _toggleControls(true);
        } else {
          _seekBy(_step);
          _toggleControls(true);
        }
        return KeyEventResult.handled;
      }
    } else {
      _bumpControls();
    }

    return KeyEventResult.ignored;
  }

  @override
  void dispose() { HardwareKeyboard.instance.removeHandler(_onRawKey);

    _saveProgress();
    for (final s in _subs) {
      s.cancel();
    }
    _hide?.cancel();
    _save?.cancel();
    _info?.cancel();
    _abr?.cancel();
    _digitTimer?.cancel();
    _zapDebounce?.cancel();
    _focus.dispose();
    _playFocus.dispose();
    _panelFocus.dispose();
    player.dispose();
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
                body: Shortcuts(
          shortcuts: !_show && !_panel && !_chanList
              ? const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.numpadEnter):
                      ActivateIntent(),
                }
              : const <ShortcutActivator, Intent>{},
          child: Actions(
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  if (!_show && !_panel && !_chanList) {
                    _toggleControls(true);
                  }
                  return null;
                },
              ),
            },
            child: Focus(

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
                    // Flux vidéo
                                    // Fond noir absolu
                const ColoredBox(color: Colors.black),
                // Flux vidéo (masqué tant que la 1re trame n'est pas décodée)
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


                    // Indicateur de chargement
                    if (_buffering && _error == null)
                      const Center(
                        child: CircularProgressIndicator(color: _kNeon),
                      ),

                    // Message d'erreur + bouton réessayer
                    if (_error != null)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.black87,
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
                                    onPressed: _openExternalPlayer,
                                    icon: const Icon(Icons.open_in_new),
                                    label: const Text('Lecteur externe'),
                                  ),
                                ],
                                                              
                              ),
                            ],
                          ),
                        ),
                      ),
                                            
                    // Saisie numérique de chaîne
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

                    // Bannière d'info zapping / EPG EN BAS
                    if (_live && (_showInfo || _show) && !_chanList)
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: _show ? 78 : 24,
                        child: _buildLiveHeader(),
                      ),

                    // Boutons d'options en bas (Chaînes, Pause, Format, Pistes & Qualité)
                    if (_show && !_chanList)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _buildBottomControls(),
                      ),

                    // Panneau latéral gauche : Liste rapide des chaînes
                    if (_live && _chanList)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 360,
                        child: _buildChannelDrawer(),
                      ),

                    // Panneau latéral droit : Qualité / Audio / Sous-titres
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
        ),
      ),
    );
  }


    Widget _buildLiveHeader() {
    final nowProg = _progs.isNotEmpty ? _progs.first : null;
    final nextProg = _progs.length > 1 ? _progs[1] : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
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
                  _title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (nowProg != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    '${_hm(nowProg.start)} - ${_hm(nowProg.end)} · ${nowProg.title}',
                    style: const TextStyle(color: _kNeon, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (nextProg != null)
                  Text(
                    'À suivre (${_hm(nextProg.start)}) : ${nextProg.title}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Text(
            _hm(DateTime.now()),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

    Widget _buildBottomControls() {
    final fitNames = <String>['Ajuster', 'Zoom', 'Étirer'];
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[Colors.black87, Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!_live) ...<Widget>[
            Text(
              _title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<Duration>(
              stream: player.stream.position,
              builder: (context, snap) {
                final pos = snap.data ?? player.state.position;
                final dur = player.state.duration;
                final maxMs = dur.inMilliseconds > 0
                    ? dur.inMilliseconds.toDouble()
                    : 1.0;
                final curMs =
                    pos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
                return Row(
                  children: <Widget>[
                    Text(_fmt(pos),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: curMs,
                        max: maxMs,
                        activeColor: _kNeon,
                        inactiveColor: Colors.white24,
                        onChanged: (v) {
                          player.seek(Duration(milliseconds: v.toInt()));
                          _bumpControls();
                        },
                      ),
                    ),
                    Text(_fmt(dur),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ],
                );
              },
            ),
          ],
                    Row(
            children: <Widget>[
              if (_live)
                _osdButton(
                  focusNode: _playFocus,
                  icon: Icons.list,
                  label: 'Chaînes',
                  onPressed: () {
                    setState(() {
                      _chanList = true;
                      _show = false;
                    });
                  },
                ),
              if (!_live)
                _osdButton(
                  icon: Icons.replay_10,
                  label: '-${_step}s',
                  onPressed: () => _seekBy(-_step),
                ),
              StreamBuilder<bool>(
                stream: player.stream.playing,
                builder: (context, snap) {
                  final playing = snap.data ?? player.state.playing;
                  return _osdButton(
                    focusNode: !_live ? _playFocus : null,
                    icon: playing ? Icons.pause : Icons.play_arrow,
                    label: playing ? 'Pause' : 'Lecture',
                    onPressed: () {
                      player.playOrPause();
                      _bumpControls();
                    },
                  );
                },
              ),

                          if (!kIsWeb)
            _osdButton(
              icon: Icons.open_in_new,
              label: 'Externe',
              onPressed: _openExternalPlayer,
            ),
              
              
              if (!_live)
                _osdButton(
                  icon: Icons.forward_10,
                  label: '+${_step}s',
                  onPressed: () => _seekBy(_step),
                ),
              const Spacer(),
              if (!_live)
                _osdButton(
                  icon: Icons.speed,
                  label: '${_rate}x',
                  onPressed: _cycleRate,
                ),
              _osdButton(
                icon: Icons.aspect_ratio,
                label: fitNames[_fit],
                onPressed: _cycleFit,
              ),
              _osdButton(
                icon: Icons.tune,
                label: 'Pistes & Qualité',
                onPressed: () {
                  setState(() {
                    _panel = true;
                    _show = false;
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _panelFocus.requestFocus();
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

      
    
  

  Widget _osdButton({
    FocusNode? focusNode,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton.icon(
        focusNode: focusNode,
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.focused)
                ? Colors.black
                : Colors.white;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.focused)
                ? _kNeon
                : Colors.white10;
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }

        Widget _buildChannelDrawer() {
    final filtered = _selectedCat == 'all'
        ? _allChannels
        : _allChannels.where((c) => c.cat == _selectedCat).toList();
    final hasActiveInFiltered = filtered
        .any((ch) => _allChannels.indexWhere((x) => x.id == ch.id) == _idx);

    return Material(
      color: const Color(0xF2101216),
      child: FocusScope(
        autofocus: true,
        child: Column(
          children: <Widget>[
            if (_cats.isNotEmpty)
              SizedBox(
                height: 52,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  itemCount: _cats.length,
                  itemBuilder: (context, i) {
                    final cat = _cats[i];
                    final sel = cat.id == _selectedCat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Focus(
                        child: Builder(
                          builder: (ctx) {
                            final focused = Focus.of(ctx).hasFocus;
                            return ChoiceChip(
                              label: Text(cat.name),
                              selected: sel,
                              selectedColor: _kNeon,
                              side: focused
                                  ? const BorderSide(
                                      color: Colors.white, width: 2.5)
                                  : BorderSide.none,
                              labelStyle: TextStyle(
                                color: sel ? Colors.black : Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              backgroundColor: Colors.white12,
                              onSelected: (_) =>
                                  setState(() => _selectedCat = cat.id),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            const Divider(height: 1, color: Colors.white24),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final ch = filtered[i];
                  final globalIdx =
                      _allChannels.indexWhere((x) => x.id == ch.id);
                  final active = globalIdx == _idx;
                  final shouldAutofocus =
                      active || (!hasActiveInFiltered && i == 0);

                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: InkWell(
                      autofocus: shouldAutofocus,
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _jumpToIndex(globalIdx),
                      child: Builder(
                        builder: (ctx) {
                          final focused = Focus.of(ctx).hasFocus;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: focused
                                  ? _kNeon.withValues(alpha: 0.30)
                                  : (active
                                      ? _kNeon.withValues(alpha: 0.14)
                                      : Colors.transparent),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: focused
                                    ? _kNeon
                                    : (active
                                        ? _kNeon.withValues(alpha: 0.4)
                                        : Colors.transparent),
                                width: focused ? 2.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: <Widget>[
                                SizedBox(
                                  width: 36,
                                  child: Text(
                                    '${globalIdx + 1}',
                                    style: TextStyle(
                                      color: (focused || active)
                                          ? _kNeon
                                          : Colors.white54,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    ch.name,
                                    style: TextStyle(
                                      color: focused
                                          ? Colors.white
                                          : (active ? _kNeon : Colors.white70),
                                      fontWeight: (focused || active)
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (active)
                                  const Icon(Icons.play_arrow_rounded,
                                      color: _kNeon, size: 20),
                              ],
                            ),
                          );
                        },
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



  Widget _buildTracksPanel() {
    final audios = player.state.tracks.audio
        .where((t) => t.id != 'auto')
        .toList();
    final subs = player.state.tracks.subtitle
        .where((t) => t.id != 'auto')
        .toList();
    final variants = _variants;

    return Material(
      color: const Color(0xEE101216),
      child: Focus(
        focusNode: _panelFocus,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            const Text('Qualité vidéo',
                style: TextStyle(
                    color: _kNeon, fontWeight: FontWeight.bold, fontSize: 15)),
            ListTile(
              autofocus: true,
              title: const Text('Auto (ABR)',
                  style: TextStyle(color: Colors.white)),
              trailing: _q == 'auto'
                  ? const Icon(Icons.check, color: _kNeon)
                  : null,
              onTap: () => _setQuality('auto'),
            ),
            for (final v in variants)
              ListTile(
                title: Text(_vLabel(v),
                    style: const TextStyle(color: Colors.white)),
                trailing: _q == v.id
                    ? const Icon(Icons.check, color: _kNeon)
                    : null,
                onTap: () => _setQuality(v.id),
              ),
            const Divider(color: Colors.white12),
            const Text('Audio',
                style: TextStyle(
                    color: _kNeon, fontWeight: FontWeight.bold, fontSize: 15)),
            for (final a in audios)
              ListTile(
                title: Text(_trackName(a.id, a.title, a.language),
                    style: const TextStyle(color: Colors.white)),
                trailing: player.state.track.audio.id == a.id
                    ? const Icon(Icons.check, color: _kNeon)
                    : null,
                onTap: () {
                  player.setAudioTrack(a);
                  setState(() {});
                },
              ),
            const Divider(color: Colors.white12),
            const Text('Sous-titres',
                style: TextStyle(
                    color: _kNeon, fontWeight: FontWeight.bold, fontSize: 15)),
            for (final s in subs)
              ListTile(
                title: Text(_trackName(s.id, s.title, s.language),
                    style: const TextStyle(color: Colors.white)),
                trailing: player.state.track.subtitle.id == s.id
                    ? const Icon(Icons.check, color: _kNeon)
                    : null,
                onTap: () {
                  player.setSubtitleTrack(s);
                  setState(() {});
                },
              ),
          ],
        ),
      ),
    );
  }
}
