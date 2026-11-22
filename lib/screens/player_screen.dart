import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  const PlayerScreen({super.key, required this.streamUrl, required this.title});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player player;
  late final VideoController controller;
  final _subs = <StreamSubscription>[];
  String? _error;
  bool _buffering = true;
  int _retries = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    player = Player();
    controller = VideoController(player);

    _subs.addAll([
      player.stream.error.listen((e) {
        if (!mounted) return;
        if (_retries < 3) {
          _retries++;
          player.open(Media(widget.streamUrl));
        } else {
          setState(() => _error = e);
        }
      }),
      player.stream.buffering.listen((b) {
        if (mounted) setState(() => _buffering = b);
      }),
      player.stream.playing.listen((p) {
        if (p) _retries = 0;
      }),
    ]);
    player.open(Media(widget.streamUrl));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
            title: Text(widget.title),
            backgroundColor: Colors.transparent,
            elevation: 0),
        body: Stack(alignment: Alignment.center, children: [
          Video(controller: controller),
          if (_buffering && _error == null) const CircularProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Lecture impossible\n$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white)),
            ),
        ]),
      );
}
