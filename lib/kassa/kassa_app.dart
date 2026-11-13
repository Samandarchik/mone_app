// kassa_app.dart — Mone ilovasi ichidagi KASSA moduli (REJA_KASSA §1.1: bitta ilova).
//
// Kassa ekranlari (kassa, ofitsiant, stollar, smena, kassa admini) `mone_pos/pos_flutter`
// dan ko'chirilgan va filial kassa serveriga (`pos_backend`) ulanadi: avval lokal
// (LAN), bo'lmasa filialning bulut nusxasi (/kassa/<filial>). Mone backend'iga
// ulanmaydi — Mone tokeni va sozlamalariga tegmaydi (kalitlar `kassa_` prefiksli).
//
// Kirish: [openKassa] — bir marta init qilib, kassani to'liq ekranda ochadi.
// Kassa o'z MaterialApp'i (navigatorKey, scaffoldMessengerKey) bilan ishlaydi —
// ko'chirilgan kod global kalitlarga tayanadi.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'core/services/api_service.dart';
import 'core/services/app_state.dart';
import 'core/services/endpoint_manager.dart';
import 'core/services/keyboard_service.dart';
import 'core/services/local_db.dart';
import 'core/services/media_cache.dart';
import 'core/services/new_order_alert_service.dart';
import 'core/services/staff_call_service.dart';
import 'core/services/tutorial_service.dart';
import 'core/services/ui_prefs.dart';
import 'core/services/wss_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_navigator.dart';
import 'core/widgets/on_screen_keyboard.dart';
import 'features/admin/admin_shell.dart';
import 'features/login/base_url_setup_screen.dart';
import 'features/login/login_screen.dart';
import 'features/pos/pos_shell.dart';

final bool _useCustomKeyboard = !kIsWeb && Platform.isWindows;

bool _kassaReady = false;

/// Kassa servislarini bir marta tayyorlaydi (server manzili, lokal kesh, holat).
Future<void> initKassa() async {
  if (_kassaReady) return;
  if (_useCustomKeyboard) KeyboardController.instance.install();
  ApiService().configure(AppMode.pos);
  await ApiService().init();
  await LocalDB().init();
  await AppState().init();
  await UiPrefs().init();
  EndpointManager().start();
  MediaCache().prune();
  _kassaReady = true;
}

/// Mone ilovasidan kassani ochish.
Future<void> openKassa(BuildContext context) async {
  final nav = Navigator.of(context);
  await initKassa();
  await nav.push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const KassaApp(),
    ),
  );
}

class KassaApp extends StatefulWidget {
  const KassaApp({super.key});
  @override
  State<KassaApp> createState() => _KassaAppState();
}

class _KassaAppState extends State<KassaApp> {
  String? _role;
  Map<String, dynamic>? _permissions;
  bool _loggedIn = false;
  bool _needsSetup = ApiService().isLocal && !ApiService().isConfigured;

  StreamSubscription<bool>? _authFailedSub;
  StreamSubscription<void>? _httpAuthFailedSub;

  @override
  void initState() {
    super.initState();
    _authFailedSub = WssService().authFailedStream.listen(
      (_) => _onAuthFailed(),
    );
    _httpAuthFailedSub = ApiService().authFailedStream.listen(
      (_) => _onAuthFailed(),
    );
    StaffCallService().start();
    NewOrderAlertService().start();
  }

  void _onAuthFailed() {
    if (!_loggedIn) return;
    _onLogout();
    appMessengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text('Sessiya tugadi — PIN kodni qayta kiriting')),
    );
  }

  @override
  void dispose() {
    _authFailedSub?.cancel();
    _httpAuthFailedSub?.cancel();
    super.dispose();
  }

  void _onLogin(String role, {Map<String, dynamic>? permissions}) {
    AppState().role = role;
    TutorialService().ensureLoaded();
    setState(() {
      _role = role;
      _permissions = permissions;
      _loggedIn = true;
    });
  }

  Future<void> _onLogout() async {
    WssService().disconnect();
    AppState().reset();
    StaffCallService().clear();
    NewOrderAlertService().clear();
    ApiService().invalidateAll();
    if (mounted) {
      setState(() {
        _role = null;
        _permissions = null;
        _loggedIn = false;
      });
    }
    await ApiService().setToken(null);
  }

  /// Kassadan Mone'ga qaytish (faqat login/sozlash ekranida — ishlayotgan
  /// smena tasodifan yopilmasin).
  void _exit() {
    WssService().disconnect();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mone Kassa',
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.unknown,
        },
      ),
      builder: (context, child) {
        final base = Listener(
          behavior: HitTestBehavior.deferToChild,
          onPointerDown: (e) => _unfocusOnOutsideTap(e.position),
          child: child ?? const SizedBox.shrink(),
        );
        return _useCustomKeyboard ? KeyboardHost(child: base) : base;
      },
      home: _buildHome(),
    );
  }

  void _unfocusOnOutsideTap(Offset position) {
    final node = FocusManager.instance.primaryFocus;
    final ctx = node?.context;
    if (node == null || ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    if (!box.size.contains(box.globalToLocal(position))) node.unfocus();
  }

  Widget _withExit(Widget child) => Stack(
        children: [
          child,
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                color: Colors.black.withValues(alpha: 0.06),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: "Mone'ga qaytish",
                  icon: const Icon(Icons.close),
                  onPressed: _exit,
                ),
              ),
            ),
          ),
        ],
      );

  Widget _buildHome() {
    if (_needsSetup) {
      return _withExit(BaseUrlSetupScreen(
        onDone: () => setState(() => _needsSetup = false),
      ));
    }
    if (!_loggedIn) {
      return _withExit(LoginScreen(onLogin: _onLogin));
    }
    switch (_role) {
      case 'super_admin':
      case 'admin':
        return AdminShell(
          onLogout: _onLogout,
          permissions: _permissions ?? {},
          role: _role ?? '',
        );
      case 'cashier':
      case 'waiter':
      case 'kitchen':
        return PosShell(onLogout: _onLogout, permissions: _permissions ?? {});
      default:
        return _withExit(LoginScreen(onLogin: _onLogin));
    }
  }
}
