import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Branded splash screen shown right after the native launch window.
///
/// Recreates the animated logo reveal (amber glow blooming on a near-black
/// background) with pure Flutter animations: a breathing glow, expanding
/// radar rings, a scale-in logo with a shimmer sweep, staggered brand text
/// entrance, and a subtle progress bar. Fades into [next] when done.
class SplashScreen extends StatefulWidget {
  final Widget next;

  const SplashScreen({super.key, required this.next});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _revealDuration = Duration(milliseconds: 2300);
  static const _glowDuration = Duration(milliseconds: 2800);

  late final AnimationController _reveal;
  late final AnimationController _glow;

  // Entrance curves for each element (staggered intervals over the reveal).
  late final Animation<double> _glowIn;
  late final Animation<double> _logoIn;
  late final Animation<double> _logoScale;
  late final Animation<double> _shimmer;
  late final Animation<double> _nameIn;
  late final Animation<double> _taglineIn;
  late final Animation<double> _progress;

  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(vsync: this, duration: _revealDuration);
    _glow = AnimationController(vsync: this, duration: _glowDuration)
      ..repeat();

    _glowIn = CurvedAnimation(
      parent: _reveal,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
    );
    _logoIn = CurvedAnimation(
      parent: _reveal,
      curve: const Interval(0.08, 0.75, curve: Curves.easeOut),
    );
    _logoScale = CurvedAnimation(
      parent: _reveal,
      curve: const Interval(0.08, 0.8, curve: Curves.easeOutBack),
    );
    _shimmer = CurvedAnimation(
      parent: _reveal,
      curve: const Interval(0.55, 1.5, curve: Curves.easeInOutCubic),
    );
    _nameIn = CurvedAnimation(
      parent: _reveal,
      curve: const Interval(0.5, 1.05, curve: Curves.easeOutCubic),
    );
    _taglineIn = CurvedAnimation(
      parent: _reveal,
      curve: const Interval(0.68, 1.25, curve: Curves.easeOutCubic),
    );
    _progress = CurvedAnimation(
      parent: _reveal,
      curve: const Interval(0.0, 1.0, curve: Curves.easeInOut),
    );

    _reveal.forward().whenComplete(_finish);
  }

  void _finish() {
    if (!mounted || _exiting) return;
    setState(() => _exiting = true);
    // Let the fade-out play before swapping in the real screen.
    Future<void>.delayed(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => widget.next,
          transitionsBuilder: (_, animation, _, child) {
            final curved =
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 1.02, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 380),
        ),
      );
    });
  }

  @override
  void dispose() {
    _reveal.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: AnimatedOpacity(
        opacity: _exiting ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        child: AnimatedBuilder(
          animation: Listenable.merge([_reveal, _glow]),
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                _background(),
                _glowHalo(),
                _radarRings(),
                _centerLogo(),
                _brand(),
              ],
            );
          },
        ),
      ),
    );
  }

  // Deep gradient base with a slightly lifted center behind the logo.
  Widget _background() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.05),
          radius: 1.05,
          colors: [
            Color(0xFF141B2E),
            AppColors.bgDark,
            Color(0xFF070A12),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
    );
  }

  // Breathing amber halo behind the logo (mimics the glow bloom of the video).
  Widget _glowHalo() {
    // Loop: bloom in on the first reveal pass, then breathe forever.
    final breath = 0.55 + 0.45 * math.sin(_glow.value * 2 * math.pi);
    final revealOpacity = _glowIn.value;
    final opacity = revealOpacity * (0.34 + 0.18 * breath);
    final scale = 0.7 + 0.55 * _glowIn.value * (1.0 + 0.12 * breath);

    return Align(
      alignment: const Alignment(0, -0.05),
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity,
          child: Container(
            width: 420,
            height: 420,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.amber.withValues(alpha: 0.28),
                  AppColors.amber.withValues(alpha: 0.10),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Expanding radar pulses that loop while the splash is visible.
  Widget _radarRings() {
    final t = _glow.value;
    return Align(
      alignment: const Alignment(0, -0.05),
      child: SizedBox(
        width: 360,
        height: 360,
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (final phase in const [0.0, 0.5]) _radarRing((t + phase) % 1.0),
          ],
        ),
      ),
    );
  }

  Widget _radarRing(double t) {
    final progress = Curves.easeOut.transform(t);
    final size = 120 + 300 * progress;
    final opacity = (1 - progress) * 0.22;
    return Opacity(
      opacity: opacity * (0.4 + 0.6 * _glowIn.value),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.amber, width: 1.4),
        ),
      ),
    );
  }

  // Logo: scale-in + fade + one shimmer sweep across the glyph.
  Widget _centerLogo() {
    final scale = 0.78 + 0.22 * _logoScale.value;
    final shimmerOffset = Tween<double>(begin: -1.4, end: 1.4)
        .transform(_shimmer.value);
    final logo = Image.asset(
      'assets/splash/logo_transparent.png',
      width: 220,
      height: 220,
      fit: BoxFit.contain,
      gaplessPlayback: true,
    );

    return Align(
      alignment: const Alignment(0, -0.05),
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: _logoIn.value,
          child: ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) {
              // Soft white sweep that travels left -> right once.
              return LinearGradient(
                begin: Alignment(-1.0 + shimmerOffset, -0.2),
                end: Alignment(-0.4 + shimmerOffset, 0.2),
                colors: [
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white.withValues(alpha: 0.55),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ).createShader(bounds);
            },
            child: logo,
          ),
        ),
      ),
    );
  }

  // Brand block: name, tagline, and the filling progress bar.
  Widget _brand() {
    final nameOpacity = Curves.easeOut.transform(_nameIn.value);
    final nameDy = 18 * (1 - _nameIn.value);
    final taglineOpacity = Curves.easeOut.transform(_taglineIn.value);

    return Align(
      alignment: const Alignment(0, 0.86),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: nameOpacity,
            child: Transform.translate(
              offset: Offset(0, nameDy),
              child: _wordmark(),
            ),
          ),
          const SizedBox(height: 10),
          Opacity(
            opacity: taglineOpacity,
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - _taglineIn.value)),
              child: Text(
                'Your AI Trading Co-Pilot',
                style: TextStyle(
                  color: AppColors.textSecondaryDark.withValues(alpha: 0.85),
                  fontSize: 13,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          const SizedBox(height: 34),
          _progressBar(),
        ],
      ),
    );
  }

  // "NEUTRAL PIP" wordmark with an amber dot and wide letter spacing.
  Widget _wordmark() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'NEUTRAL',
          style: TextStyle(
            color: AppColors.textPrimaryDark,
            fontSize: 22,
            letterSpacing: 6,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.amber,
            boxShadow: [
              BoxShadow(
                color: Color(0x66F5B800),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'PIP',
          style: TextStyle(
            color: AppColors.amber,
            fontSize: 22,
            letterSpacing: 6,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ],
    );
  }

  Widget _progressBar() {
    return Container(
      width: 150,
      height: 2.5,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevatedDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: 0.06 + 0.94 * _progress.value,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.amberDim, AppColors.amber, AppColors.amberStrong],
            ),
          ),
        ),
      ),
    );
  }
}
