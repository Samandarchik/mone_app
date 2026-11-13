import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/services/api_service.dart';
import '../../core/services/app_state.dart';
import '../../core/services/wss_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/connection_indicator.dart';
import 'base_url_setup_screen.dart';

class LoginScreen extends StatefulWidget {
  final Function(String role, {Map<String, dynamic>? permissions}) onLogin;
  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // PIN login (local)
  String _pin = '';
  bool _loading = false;
  String? _error;

  // Phone+PIN login (cloud)
  final _phoneController = TextEditingController();
  final _cloudPinController = TextEditingController();

  bool get _isLocal => ApiService().isLocal;

  void _onDigit(String digit) {
    if (_pin.length >= 4 || _loading) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == 4) {
      _loginByPin();
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty || _loading) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  void _onClear() {
    if (_loading) return;
    setState(() {
      _pin = '';
      _error = null;
    });
  }

  Future<void> _loginByPin() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService().loginByPin(_pin);
      await _handleLoginSuccess(res);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _loginError(e, 'PIN noto\'g\'ri');
          _pin = '';
        });
      }
    } finally {
      // `mounted` SHART: muvaffaqiyatli loginda ekran allaqachon
      // almashtirilgan bo'ladi.
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Login xatosini ANIQ ko'rsatadi. Ilgari hamma xato "PIN noto'g'ri" deb
  /// chiqardi: server o'chgan bo'lsa ham, internet uzilgan bo'lsa ham,
  /// urinishlar limiti tugagan bo'lsa ham — xodim PINini bejiz qidirardi.
  String _loginError(Object e, String wrongCredsMsg) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 429) {
        final data = e.response?.data;
        if (data is Map && data['message'] != null) return data['message'].toString();
        return 'Juda ko\'p urinish — bir necha daqiqadan so\'ng qayta urining';
      }
      if (code == 401 || code == 403) return wrongCredsMsg;
      if (code != null && code >= 500) {
        return 'Server xatosi ($code) — qayta urining';
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return 'Server javob bermadi — tarmoqni tekshiring';
        case DioExceptionType.connectionError:
        case DioExceptionType.unknown:
          return 'Serverga ulanib bo\'lmadi — server yoqilganini tekshiring';
        default:
          break;
      }
    }
    if (e is FormatException) {
      return 'Server noto‘g‘ri javob qaytardi — manzilni tekshiring';
    }
    return wrongCredsMsg;
  }

  @override
  void dispose() {
    // Ilgari bu klass'da `dispose()` UMUMAN yo'q edi — har login ekrani
    // ochilganda ikkita controller va ularning tinglovchilari qolib
    // ketardi.
    _phoneController.dispose();
    _cloudPinController.dispose();
    super.dispose();
  }

  Future<void> _loginByPhone() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final phone = '+998${_phoneController.text.trim()}';
      final res = await ApiService().login(phone, _cloudPinController.text.trim());
      await _handleLoginSuccess(res);
    } catch (e) {
      if (mounted) {
        setState(() => _error = _loginError(e, 'Telefon yoki PIN noto\'g\'ri'));
      }
    } finally {
      // `mounted` SHART: login muvaffaqiyatli bo'lsa ekran allaqachon
      // almashtirilgan bo'ladi va `setState` "called after dispose"
      // xatosini berardi.
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleLoginSuccess(Map<String, dynamic> res) async {
    // Javob SHAKLINI tekshiramiz.
    //
    // Ilgari bu uch qator shartsiz `as` cast edi. Captive-portal sahifasi
    // yoki proxy 200 bilan boshqa JSON qaytarsa `TypeError` chiqar, uni
    // yuqoridagi `catch` ushlab, ekranga "PIN noto'g'ri" deb yozardi —
    // ya'ni kassir PINini qayta-qayta terib, muammo tarmoqdaligini
    // umuman bilmasdi.
    final token = res['token'];
    final user = res['user'];
    if (token is! String || token.isEmpty || user is! Map) {
      throw const FormatException('server_response_invalid');
    }
    final role = user['role'];
    if (role is! String || role.isEmpty) {
      throw const FormatException('server_response_invalid');
    }

    // Ism admin panelida (yon panel pastida) ko'rsatiladi.
    final name = user['name'];
    AppState().userName = name is String && name.trim().isNotEmpty ? name : null;

    await ApiService().setToken(token);
    WssService().connect(
      token: token,
      source: role == 'super_admin' ? 'phone' : 'pos',
    );
    final rawPerms = user['permissions'];
    final perms = rawPerms is Map
        ? Map<String, dynamic>.from(rawPerms)
        : <String, dynamic>{};
    widget.onLogin(role, permissions: perms);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            // Klaviatura past ekranga sig'masligi mumkin (landshaft
            // rejimdagi telefon) — aylantirib chiqiladi
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: _isLocal ? _buildPinLogin() : _buildPhoneLogin(),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const EndpointBadge(),
                  const SizedBox(width: 10),
                  _topButton(
                    icon: Icons.dns_rounded,
                    label: 'Server',
                    onTap: _changeServerUrl,
                  ),
                  if (_isLocal) ...[
                    const SizedBox(width: 10),
                    _topButton(
                      icon: Icons.close,
                      label: 'Chiqish',
                      onTap: () => exit(0),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeServerUrl() async {
    final changed = await showServerUrlSheet(context);
    if (!mounted || !changed) return;
    setState(() {
      _pin = '';
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Server manzili: ${ApiService().baseUrl}')),
    );
  }

  Widget _topButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final big = context.isTabletUi;
    return Material(
      color: AppColors.surfaceAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: big ? 18 : 16, vertical: big ? 12 : 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: big ? 20 : 18, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: big ? 15 : 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Klaviatura tugmasining o'lchami — ekranga qarab.
  ///
  /// ILGARI: 72pt qat'iy edi. 13 dyuymli planshetda butun PIN paneli
  /// ekranning uchdan biriga siqilib, uzoqdan turib bosish qiyin edi;
  /// iPhone SE da esa aksincha — 4 ta nuqta va 320pt panel ekran chetiga
  /// tegib turardi.
  double get _keySize {
    final size = MediaQuery.sizeOf(context);
    if (size.width >= AppBreakpoints.phone) {
      // Planshet: balandlikka ham qaraymiz — klaviatura ekranga sig'sin
      return (size.height * 0.085).clamp(80.0, 104.0);
    }
    if (size.width < AppBreakpoints.smallPhone) return 62.0;
    return 72.0;
  }

  Widget _buildPinLogin() {
    final key = _keySize;
    final gap = key * 0.22;
    final big = context.isTabletUi;

    return SizedBox(
      width: key * 3 + gap * 4,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'MONE KASSA',
            style: TextStyle(
              fontSize: big ? 44 : 32,
              fontWeight: FontWeight.w800,
              letterSpacing: big ? 9 : 6,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'PIN kodni kiriting',
            style: TextStyle(
                color: AppColors.textMuted, fontSize: big ? 18 : 15),
          ),
          SizedBox(height: big ? 44 : 36),
          // PIN dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final filled = i < _pin.length;
              final d = big ? 24.0 : 20.0;
              return AnimatedContainer(
                duration: AppDuration.fast,
                margin: EdgeInsets.symmetric(horizontal: big ? 13 : 10),
                width: d,
                height: d,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled
                      ? (_error != null ? AppColors.danger : AppColors.primary)
                      : Colors.transparent,
                  border: Border.all(
                    color: _error != null
                        ? AppColors.danger
                        : AppColors.borderStrong,
                    width: 2,
                  ),
                ),
              );
            }),
          ),
          // Xato yozuvi uchun joy DOIM band turadi: ilgari yozuv chiqqanda
          // klaviatura pastga surilib, raqam bosilganda (xato tozalanib)
          // yana tepaga sakrardi — tugmani mo'ljalga olish qiyin edi.
          SizedBox(
            height: big ? 64 : 54,
            child: Center(
              child: _error == null
                  ? null
                  : Text(
                      _error!,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppColors.danger,
                          fontSize: big ? 15 : 13.5,
                          fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          // Number pad
          _buildNumPad(key, gap),
          // Spinner uchun ham joy doim band — markazlangan ustun yuklanish
          // paytida yuqoriga surilib ketmasin.
          SizedBox(
            height: 44,
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildNumPad(double key, double gap) {
    return Column(
      children: [
        _numRow(['1', '2', '3'], key, gap),
        SizedBox(height: gap),
        _numRow(['4', '5', '6'], key, gap),
        SizedBox(height: gap),
        _numRow(['7', '8', '9'], key, gap),
        SizedBox(height: gap),
        _numRow(['C', '0', '<'], key, gap),
      ],
    );
  }

  Widget _numRow(List<String> keys, double key, double gap) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: keys.map((k) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: gap / 2),
          child: _numButton(k, key),
        );
      }).toList(),
    );
  }

  Widget _numButton(String key, double size) {
    final isAction = key == 'C' || key == '<';
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: isAction ? AppColors.surfaceAlt : AppColors.surface,
        shape: CircleBorder(
          side: BorderSide(
            color: isAction ? Colors.transparent : AppColors.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _loading
              ? null
              : () {
                  if (key == 'C') {
                    _onClear();
                  } else if (key == '<') {
                    _onBackspace();
                  } else {
                    _onDigit(key);
                  }
                },
          child: Center(
            child: key == '<'
                ? Icon(Icons.backspace_outlined,
                    size: size * 0.32, color: AppColors.textMuted)
                : Text(
                    key,
                    style: TextStyle(
                      fontSize: isAction ? size * 0.24 : size * 0.38,
                      fontWeight: FontWeight.w600,
                      color: isAction ? AppColors.textMuted : AppColors.text,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneLogin() {
    return Container(
      width: 360,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'MONE KASSA',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Tizimga kirish',
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
          const SizedBox(height: 40),
          TextField(
            controller: _phoneController,
            decoration: InputDecoration(
              labelText: 'Telefon raqam',
              prefixText: '+998 ',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.phone),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _cloudPinController,
            decoration: InputDecoration(
              labelText: 'PIN kod',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.lock),
            ),
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _loading ? null : _loginByPhone,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Kirish',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
