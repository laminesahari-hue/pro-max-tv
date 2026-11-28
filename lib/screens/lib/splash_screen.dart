import 'dart:async';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final Widget nextScreen;
  const SplashScreen({super.key, required this.nextScreen});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeIn,
    );

    _scale = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );

    _ctrl.forward();

    _timer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, __, ___) => widget.nextScreen,
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const neonGreen = Color(0xFF69F028);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0D12),
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: neonGreen.withOpacity(0.18),
                        blurRadius: 48,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/banner.png',
                    width: 420,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 36),
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.8,
                    color: neonGreen,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
