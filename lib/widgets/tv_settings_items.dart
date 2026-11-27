import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Ligne cliquable (avec flèche >) compatible télécommande TV
class TvNavTile extends StatefulWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool autofocus;

  const TvNavTile({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<TvNavTile> createState() => _TvNavTileState();
}

class _TvNavTileState extends State<TvNavTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _focused ? const Color(0xFF4ADE80).withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused ? const Color(0xFF4ADE80) : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: _focused ? const Color(0xFF4ADE80) : Colors.white70, size: 22),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white)),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(widget.subtitle!,
                          style: const TextStyle(fontSize: 13, color: Colors.white60)),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: _focused ? const Color(0xFF4ADE80) : Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ligne avec bouton ON/OFF (Switch) contrôlable avec le bouton OK de la télécommande
class TvSwitchTile extends StatefulWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const TvSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  State<TvSwitchTile> createState() => _TvSwitchTileState();
}

class _TvSwitchTileState extends State<TvSwitchTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onChanged(!widget.value);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: () => widget.onChanged(!widget.value),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _focused ? const Color(0xFF4ADE80).withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused ? const Color(0xFF4ADE80) : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white)),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(widget.subtitle!,
                          style: const TextStyle(fontSize: 13, color: Colors.white60)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ExcludeFocus(
                child: Switch(
                  value: widget.value,
                  activeColor: Colors.black,
                  activeTrackColor: const Color(0xFF4ADE80),
                  onChanged: widget.onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
