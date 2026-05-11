import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/login_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/main.dart' show firebaseReady;
import 'package:itp_voice/notification_service.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/widgets/custom_toast.dart';
import 'package:url_launcher/url_launcher.dart';

// Login brand palette — mirrors voice360-fe-redesign Login.jsx
// (Tailwind purple-600 → violet-600). Intentionally hardcoded here rather
// than added to V360Colors because the rest of the mobile app stays on the
// design-system sky-blue primary — only the auth screen leans purple.
const Color _kBrandPurple600 = Color(0xFF9333EA);
const Color _kBrandViolet600 = Color(0xFF7C3AED);
const Color _kBrandPurple700 = Color(0xFF7E22CE);
const Color _kBrandIndigo950 = Color(0xFF1E1B4B);
const Color _kBrandIndigo900 = Color(0xFF312E81);

const String _kWebAppUrl = 'https://app.voice360.app';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final LoginController con = Get.put(LoginController());
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _wirePushHandlers();
  }

  void _wirePushHandlers() {
    // Without Firebase initialized (iOS pre-GoogleService-Info.plist), every
    // FirebaseMessaging touch throws `[core/no-app]`. No-op out cleanly.
    if (!firebaseReady) return;
    FirebaseMessaging.instance.getInitialMessage().then((message) async {
      if (message?.data == null) return;
      final data = message!.data;
      if (data.containsKey('message_thread_id')) {
        await Get.toNamed(
          Routes.CHAT_SCREEN_ROUTE,
          arguments: [data['message_thread_id'], data['to_phone_number'], null],
        );
        if (con.initializedd == true) {
          Get.offAllNamed(Routes.BASE_SCREEN_ROUTE);
        }
      }
    });

    FirebaseMessaging.onMessage.listen((message) {
      if (message.notification == null) return;
      if (Get.currentRoute != Routes.CHAT_SCREEN_ROUTE) {
        LocalNotificationService.createanddisplaynotification(message);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final data = message.data;
      if (data.containsKey('message_thread_id')) {
        Get.toNamed(
          Routes.CHAT_SCREEN_ROUTE,
          arguments: [data['message_thread_id'], data['to_phone_number'], null],
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: cs.surface,
        body: Obx(
          () => con.showLogin.value ? _buildLogin(context) : _buildSplash(context),
        ),
      ),
    );
  }

  Widget _buildSplash(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kBrandIndigo950, _kBrandIndigo900, _kBrandPurple700],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(V360Radius.xxl),
                boxShadow: V360Shadows.md,
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(14),
              child: Image.asset(
                'assets/images/v360_logo_purp.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.phone_in_talk_rounded,
                  color: _kBrandPurple600,
                  size: 48,
                ),
              ),
            ),
            const SizedBox(height: V360Spacing.s6),
            const Text(
              'VOICE360',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: V360Spacing.s2),
            Text(
              'Calls. Messages. Voicemail.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: V360Spacing.s10),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogin(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: V360Spacing.s6,
            vertical: V360Spacing.s8,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Image.asset(
                    'assets/images/v360_logo_purp.png',
                    height: 64,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_kBrandPurple600, _kBrandViolet600],
                        ),
                        borderRadius: BorderRadius.circular(V360Radius.xl),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.phone_in_talk_rounded,
                          color: Colors.white, size: 36),
                    ),
                  ),
                ),
                const SizedBox(height: V360Spacing.s6),
                Center(
                  child: Text(
                    'Welcome Back',
                    style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: V360Spacing.s1),
                Center(
                  child: Text(
                    'Sign in to your Voice360 account to continue',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: V360Spacing.s8),
                _label(context, 'Email'),
                const SizedBox(height: V360Spacing.s2),
                TextField(
                  controller: con.emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (con.errorMessage.value.isNotEmpty) {
                      con.errorMessage.value = '';
                    }
                  },
                  decoration: const InputDecoration(
                    hintText: 'you@company.com',
                    prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: V360Spacing.s5),
                _label(context, 'Password'),
                const SizedBox(height: V360Spacing.s2),
                TextField(
                  controller: con.passwordController,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => con.login(),
                  onChanged: (_) {
                    if (con.errorMessage.value.isNotEmpty) {
                      con.errorMessage.value = '';
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Enter your password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: V360Spacing.s3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Obx(() => Row(
                          children: [
                            Checkbox(
                              value: con.isRemember.value,
                              onChanged: (v) =>
                                  con.isRemember.value = v ?? false,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(V360Radius.base),
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: V360Spacing.s1),
                            Text(
                              'Remember me',
                              style: tt.bodyMedium,
                            ),
                          ],
                        )),
                  ],
                ),
                Obx(() {
                  final err = con.errorMessage.value;
                  if (err.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: V360Spacing.s3),
                    child: _ErrorBanner(message: err),
                  );
                }),
                const SizedBox(height: V360Spacing.s5),
                Obx(() => _PrimaryButton(
                      label: con.isLoading.value ? 'Signing In…' : 'Sign In',
                      loading: con.isLoading.value,
                      onPressed: con.isLoading.value ? null : con.login,
                    )),
                const SizedBox(height: V360Spacing.s4),
                _OrDivider(),
                const SizedBox(height: V360Spacing.s4),
                Obx(() => _SsoButton(
                      label: 'Continue with Google',
                      icon: _googleIcon(),
                      onPressed: con.isLoading.value
                          ? null
                          : () => con.loginWithSso('google'),
                    )),
                const SizedBox(height: V360Spacing.s3),
                Obx(() => _SsoButton(
                      label: 'Continue with Microsoft',
                      icon: _microsoftIcon(),
                      onPressed: con.isLoading.value
                          ? null
                          : () => con.loginWithSso('microsoft'),
                    )),
                const SizedBox(height: V360Spacing.s5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _FooterLink(
                      label: 'Forgot Password?',
                      onTap: () => _launchWeb('/reset-pw'),
                    ),
                    const SizedBox(width: V360Spacing.s4),
                    _FooterLink(
                      label: 'Create Account',
                      onTap: () => _launchWeb('/Sign-Up'),
                    ),
                  ],
                ),
                const SizedBox(height: V360Spacing.s6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: V360Spacing.s1),
                    Text(
                      'Secured by ITP 360',
                      style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _launchWeb(String path) async {
    final uri = Uri.parse('$_kWebAppUrl$path');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      CustomToast.showToast('Could not open browser.', true);
    }
  }

  Widget _googleIcon() => SizedBox(
        width: 20,
        height: 20,
        child: CustomPaint(painter: _GoogleGlyphPainter()),
      );

  Widget _microsoftIcon() => SizedBox(
        width: 18,
        height: 18,
        child: CustomPaint(painter: _MicrosoftGlyphPainter()),
      );

  Widget _label(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Opacity(
      opacity: disabled ? 0.7 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(V360Radius.lg),
          onTap: onPressed,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [_kBrandPurple600, _kBrandViolet600],
              ),
              borderRadius: BorderRadius.circular(V360Radius.lg),
              boxShadow: disabled ? null : V360Shadows.sm,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading) ...[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                  const SizedBox(width: V360Spacing.s2),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    letterSpacing: 0.2,
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

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Divider(color: cs.outlineVariant, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: V360Spacing.s3),
          child: Text(
            'OR',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Expanded(child: Divider(color: cs.outlineVariant, height: 1)),
      ],
    );
  }
}

class _SsoButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  const _SsoButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disabled = onPressed == null;
    return Opacity(
      opacity: disabled ? 0.6 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(V360Radius.lg),
          onTap: onPressed,
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(V360Radius.lg),
              border: Border.all(color: cs.outlineVariant),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: V360Spacing.s3),
                Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
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

class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _FooterLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: _kBrandPurple600,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _GoogleGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Stylized "G" — simple multi-color stroke approximation.
    // Good enough at 20px; a tiny SVG would be nicer if flutter_svg was added.
    final stroke = size.width * 0.18;
    final r = (size.width - stroke) / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: c, radius: r);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, 3.14, 1.05, false, paint);
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 3.14 - 1.05, 1.05, false, paint);
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 0, 1.0, false, paint);
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, 1.0, 1.1, false, paint);

    // Inner crossbar
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = stroke * 0.9
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(
      Offset(c.dx + r * 0.05, c.dy),
      Offset(c.dx + r * 0.95, c.dy),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MicrosoftGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final tileW = (w - 1) / 2;
    final tileH = (h - 1) / 2;
    final paint = Paint();

    paint.color = const Color(0xFFF25022);
    canvas.drawRect(Rect.fromLTWH(0, 0, tileW, tileH), paint);
    paint.color = const Color(0xFF7FBA00);
    canvas.drawRect(Rect.fromLTWH(tileW + 1, 0, tileW, tileH), paint);
    paint.color = const Color(0xFF00A4EF);
    canvas.drawRect(Rect.fromLTWH(0, tileH + 1, tileW, tileH), paint);
    paint.color = const Color(0xFFFFB900);
    canvas.drawRect(Rect.fromLTWH(tileW + 1, tileH + 1, tileW, tileH), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V360Spacing.s3,
        vertical: V360Spacing.s3,
      ),
      decoration: BoxDecoration(
        color: V360Colors.danger50,
        borderRadius: BorderRadius.circular(V360Radius.lg),
        border: Border.all(color: V360Colors.danger500.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: V360Colors.danger600,
            size: 18,
          ),
          const SizedBox(width: V360Spacing.s2),
          Expanded(
            child: Text(
              message,
              style: tt.bodyMedium?.copyWith(
                color: V360Colors.danger700,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
