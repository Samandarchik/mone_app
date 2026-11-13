import 'package:flutter/material.dart';
import '../../core/services/api_service.dart';
import '../../core/services/endpoint_manager.dart';
import '../../core/theme/app_theme.dart';

/// Server manzilini kiritish/tahrirlash formasi.
///
/// **Faqat bitta manzil so'raladi** — asosiy (online) server. Restoran ichidagi
/// local server ilovaning o'zi tomonidan topiladi: Windows master'da ilova
/// server bilan bitta mashinada turadi, shuning uchun ishga tushishda
/// `localhost:3000` so'raladi va javob bersa ish o'sha yerdan yuritiladi.
///
/// Planshet/boshqa terminalda localhost'da server yo'q — ular uchun standart
/// LAN manzili ([kLanServerUrl]) avtomatik sinab ko'riladi. "LAN manzil"
/// maydoni faqat boshqa tarmoq/restoran uchun kerak: bo'sh qolsa ham standart
/// manzil tekshiriladi, javob bermasa terminal online server bilan ishlaydi.
class _EndpointFields extends StatelessWidget {
  final TextEditingController serverC;
  final TextEditingController lanC;
  final String? serverError;
  final String? lanError;
  final VoidCallback onSubmit;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  const _EndpointFields({
    required this.serverC,
    required this.lanC,
    required this.serverError,
    required this.lanError,
    required this.onSubmit,
    required this.onChanged,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: serverC,
          autofocus: autofocus,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: 'Server manzili',
            hintText: kServerUrl,
            helperText: 'Asosiy manzil — local server o‘zi topiladi',
            prefixIcon: const Icon(Icons.dns_rounded),
            errorText: serverError,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: lanC,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmit(),
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: 'LAN manzil (ixtiyoriy)',
            hintText: kLanServerUrl,
            helperText: "Restoran ichidagi manzil — bo'sh qolsa standart sinaladi",
            prefixIcon: const Icon(Icons.lan_rounded),
            errorText: lanError,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
      ],
    );
  }
}

/// Kiritilgan manzillarni tekshirib saqlaydi. Xato bo'lsa (serverXato, lanXato)
/// qaytaradi, muvaffaqiyatli bo'lsa (null, null).
Future<(String?, String?)> _saveEndpoints(String server, String lan) async {
  final serverRaw = server.trim();
  final lanRaw = lan.trim();
  if (!ApiService.isValidUrl(serverRaw)) {
    return ("To'g'ri server manzilini kiriting", null);
  }
  if (lanRaw.isNotEmpty && !ApiService.isValidUrl(lanRaw)) {
    return (null, "To'g'ri LAN manzilini kiriting");
  }
  await ApiService().setEndpoints(serverUrl: serverRaw, lanUrl: lanRaw);
  return (null, null);
}

/// Birinchi ochilishda server manzilini so'raydigan ekran.
class BaseUrlSetupScreen extends StatefulWidget {
  final VoidCallback onDone;
  const BaseUrlSetupScreen({super.key, required this.onDone});

  @override
  State<BaseUrlSetupScreen> createState() => _BaseUrlSetupScreenState();
}

class _BaseUrlSetupScreenState extends State<BaseUrlSetupScreen> {
  late final TextEditingController _serverC =
      TextEditingController(text: ApiService().cloudUrl ?? kServerUrl);
  late final TextEditingController _lanC =
      TextEditingController(text: ApiService().lanUrl ?? kLanServerUrl);
  bool _saving = false;
  String? _serverError;
  String? _lanError;

  @override
  void dispose() {
    _serverC.dispose();
    _lanC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final (se, le) = await _saveEndpoints(_serverC.text, _lanC.text);
    if (!mounted) return;
    if (se != null || le != null) {
      setState(() {
        _saving = false;
        _serverError = se;
        _lanError = le;
      });
      return;
    }
    widget.onDone();
  }

  void _clearErrors(String _) {
    if (_serverError != null || _lanError != null) {
      setState(() {
        _serverError = null;
        _lanError = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: const Icon(Icons.dns_rounded,
                      size: 32, color: AppColors.primary),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Server manzili',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ilova ulanadigan serverni kiriting',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 15),
                ),
                const SizedBox(height: 32),
                _EndpointFields(
                  serverC: _serverC,
                  lanC: _lanC,
                  serverError: _serverError,
                  lanError: _lanError,
                  onSubmit: _save,
                  onChanged: _clearErrors,
                  autofocus: true,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Davom etish',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
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

/// Server manzilini keyinchalik o'zgartirish uchun modal (sozlamalardan
/// chaqiriladi). Manzil o'zgarsa `true` qaytaradi.
Future<bool> showServerUrlSheet(BuildContext context) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _ServerUrlSheet(),
  );
  return changed ?? false;
}

class _ServerUrlSheet extends StatefulWidget {
  const _ServerUrlSheet();

  @override
  State<_ServerUrlSheet> createState() => _ServerUrlSheetState();
}

class _ServerUrlSheetState extends State<_ServerUrlSheet> {
  late final TextEditingController _serverC =
      TextEditingController(text: ApiService().cloudUrl ?? kServerUrl);
  late final TextEditingController _lanC =
      TextEditingController(text: ApiService().lanUrl ?? kLanServerUrl);
  bool _saving = false;
  String? _serverError;
  String? _lanError;

  @override
  void dispose() {
    _serverC.dispose();
    _lanC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final (se, le) = await _saveEndpoints(_serverC.text, _lanC.text);
    if (!mounted) return;
    if (se != null || le != null) {
      setState(() {
        _saving = false;
        _serverError = se;
        _lanError = le;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  void _clearErrors(String _) {
    if (_serverError != null || _lanError != null) {
      setState(() {
        _serverError = null;
        _lanError = null;
      });
    }
  }

  /// Saqlangan manzillar orasida qo'lda almashish (tahrirlanayotgan matnga
  /// tegmaydi — avval «Saqlash» bosilishi kerak).
  void _switchNow(bool toCloud) {
    final ok = toCloud
        ? EndpointManager().forceCloud()
        : EndpointManager().forceLocal();
    if (ok) Navigator.of(context).pop(true);
  }

  /// Local serverni shu yerdayoq qayta izlash — server ilovadan keyin
  /// ko'tarilgan bo'lsa 15 soniyalik davriy tekshiruvni kutmaslik uchun.
  Future<void> _detectNow() async {
    setState(() => _saving = true);
    final found = await ApiService().detectLocal();
    if (!mounted) return;
    setState(() => _saving = false);
    if (found) {
      EndpointManager().forceLocal();
      if (mounted) Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local server topilmadi')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final api = ApiService();
    final onCloud = api.isUsingCloud;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dns_rounded, color: AppColors.primary),
                const SizedBox(width: 10),
                const Text(
                  'Server manzili',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: onCloud
                        ? AppColors.warningSoft
                        : AppColors.successSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    onCloud ? 'Hozir: ONLINE' : 'Hozir: LOCAL',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: onCloud ? AppColors.warning : AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              api.hasLocal
                  ? 'Local server topildi: ${api.localUrl}'
                  : 'Local server topilmadi — ish online serverda',
              style: TextStyle(
                fontSize: 12,
                color: api.hasLocal ? AppColors.success : AppColors.textFaint,
              ),
            ),
            const SizedBox(height: 14),
            _EndpointFields(
              serverC: _serverC,
              lanC: _lanC,
              serverError: _serverError,
              lanError: _lanError,
              onSubmit: _save,
              onChanged: _clearErrors,
              autofocus: true,
            ),
            Row(
              children: [
                // Avto-almashish yetarli bo'lmagan holatlar uchun (masalan
                // local ko'tarilgan, lekin noto'g'ri ishlayapti) — qo'lda o'tish.
                if (api.hasLocal)
                  TextButton.icon(
                    onPressed: _saving ? null : () => _switchNow(!onCloud),
                    icon: Icon(
                      onCloud ? Icons.lan_rounded : Icons.cloud_outlined,
                      size: 18,
                    ),
                    label: Text(
                      onCloud ? 'Localga o‘tish' : 'Onlinega o‘tish',
                      style: const TextStyle(fontSize: 13),
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: _saving ? null : _detectNow,
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text(
                      'Local serverni izlash',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded, size: 20),
                label: const Text('Saqlash',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
