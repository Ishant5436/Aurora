import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/hero_art.dart';
import '../widgets/renaissance.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 3200), _enter);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _enter() {
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _enter,
      child: Screen(
        center: true,
        background: const Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: 0.6,
            widthFactor: 1,
            child: HeroArt(opacity: 0.4, alignment: Alignment.bottomCenter),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.primary),
                boxShadow: c.glow,
              ),
              child: Icon(Icons.alarm, size: 36, color: c.primary),
            ),
            const SizedBox(height: 24),
            GoldText(kAppName, style: Typo.display(48)),
            const Ornament(padding: EdgeInsets.symmetric(vertical: 20)),
            Text(kTagline, style: Typo.serif(22, italic: true, color: c.foreground)),
            const SizedBox(height: 40),
            Text('TAP TO ENTER', style: Typo.sans(12, color: c.mutedForeground, letterSpacing: 3.6)),
          ],
        ),
      ),
    );
  }
}
