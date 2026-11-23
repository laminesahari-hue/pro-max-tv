  void _jump(int i) {
    final n = widget.channels!.length;
    if (n == 0 || i == _idx) return;
    _prevIdx = _idx;
    _idx = (i % n + n) % n;
    _retries = 0;
    _progs = <Programme>[];
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

  Widget _quick(IconData icon, String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
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
              colors: <Color>[Colors.black87, Colors.transparent],
            ),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            if (_show)
              IconButton(
                icon: const Icon(Icons.arrow_back_ios),
                onPressed: () => Navigator.of(context).pop(),
              )
            else
              const SizedBox(width: 12),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
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
                child: const Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Icon(Icons.circle, size: 8),
                  SizedBox(width: 6),
                  Text('En Direct',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                ]),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(
                    _live && _item.number > 0 ? '${_item.number}  $_title' : _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                if (_live && _progs.isNotEmpty)
                  Text('Maintenant : ${_progs.first.title}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                if (_live && _progs.length > 1)
                  Text('Ensuite : ${_progs.elementAt(1).title}',
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
          return Row(children: <Widget>[
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
      child: Row(children: <Widget>[
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
              colors: <Color>[Colors.black87, Colors.transparent],
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
              _quick(Icons.subtitles_outlined, 'Langues et\nSous-titres', _openPanel),
              _quick(Icons.hd_outlined, 'Qualité\nVidéo', _openPanel),
              _quick(Icons.settings_outlined, 'Paramètres\nAvancés', _togglePanel),
              if (_live)
                _quick(Icons.format_list_bulleted, 'Liste des\nchaînes', _openChanList),
            ]),
            const SizedBox(height: 8),
            if (_live) _epgBar() else _seekBar(),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
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
