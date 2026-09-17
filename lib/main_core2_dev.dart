// main_core2_dev.dart — FAQAT SINOV uchun kirish nuqtasi: Mone login'isiz
// to'g'ridan-to'g'ri Ombor 2.0 «Bugun» sahifasini ochadi (mone_core kodi bilan
// kiradi). Ishlab chiqarish ilovasiga ta'sir qilmaydi (`main.dart` o'zgarmagan).
//
//   flutter build web --release -t lib/main_core2_dev.dart \
//     --dart-define=CORE_CODE=1001 --dart-define=CORE_URL=http://host:1020
//
// `CORE_CODE` — mone_core foydalanuvchi kodi (1001 — Xilola, bugalter).
// `CORE_URL` — yadro manzili; bo'sh bo'lsa saqlangan/standart manzil ishlatiladi
// («Server» tugmasi orqali ham almashtirsa bo'ladi).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uz_ai_dev/core/config/server_config.dart';
import 'package:uz_ai_dev/core/widgets/server_settings_dialog.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_docs_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_stock_provider.dart';
import 'package:uz_ai_dev/core2/ui/core_home_ui.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

const String _code = String.fromEnvironment('CORE_CODE', defaultValue: '1001');
const String _coreUrl = String.fromEnvironment('CORE_URL', defaultValue: '');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  ServerConfig.load(prefs);
  if (_coreUrl.isNotEmpty) await ServerConfig.save(coreUrl: _coreUrl);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CoreSession()),
        ChangeNotifierProvider(create: (_) => CoreDictProvider()),
        ChangeNotifierProvider(create: (_) => CoreDocsProvider()),
        ChangeNotifierProvider(create: (_) => CoreStockProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Ombor 2.0 (sinov)',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: kCoreAccent,
          scaffoldBackgroundColor: kCoreBg,
        ),
        home: const _Gate(),
      ),
    ),
  );
}

/// Kod bilan kirish darvozasi: muvaffaqiyatli bo'lsa «Bugun», aks holda
/// sabab + «Qayta urinish» / «Server» tugmalari.
class _Gate extends StatefulWidget {
  const _Gate();

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  bool _busy = true;
  bool _ok = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _login());
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    final session = context.read<CoreSession>();
    final ok = await session.loginWithCode(_code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = ok;
      _err = ok
          ? null
          : (session.error ?? 'Kirish xato (kod $_code)');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ok) return const CoreHomeUi();
    return Scaffold(
      backgroundColor: kCoreBg,
      body: Center(
        child: _busy
            ? const CircularProgressIndicator.adaptive()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_off, size: 56, color: Colors.grey.shade500),
                    const SizedBox(height: 12),
                    const Text('Ombor 2.0 ga kirilmadi',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      '${_err ?? ''}\nKod: $_code · Server: ${ServerConfig.coreUrl}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _login,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: kCoreAccent,
                              foregroundColor: Colors.white),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Qayta urinish'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final saved = await showServerSettingsDialog(context);
                            if (saved && mounted) _login();
                          },
                          icon: const Icon(Icons.dns_outlined),
                          label: const Text('Server'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
