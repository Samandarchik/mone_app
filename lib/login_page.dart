// login_page.dart — kirish ekrani (LoginPage): v1 parol-bilan login
// (ApiService.loginV1), token/role/is_admin'ni SharedPreferences'ga saqlaydi va
// _navigateByRole orqali rolga mos Home'ga o'tadi. Muvaffaqiyatli login'dan
// keyin o'sha kod bilan FONDA mone_core (/api/v2/auth/login) ga ham kiriladi
// (CoreSession.loginWithCode) — xato bo'lsa ilova to'xtamaydi. Pastdagi ⚙
// «Server» tugmasi base_url/core_url sozlash dialogini ochadi.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uz_ai_dev/admin/ui/admin_home_ui.dart';
import 'package:uz_ai_dev/bugalter/ui/bugalter_home_ui.dart';
import 'package:uz_ai_dev/core/config/server_config.dart';
import 'package:uz_ai_dev/core/constants/roles.dart';
import 'package:uz_ai_dev/core/data/sklad_registry.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core/widgets/server_settings_dialog.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/ombor/ui/ombor_home_ui.dart';
import 'package:uz_ai_dev/shef/ui/shef_home_ui.dart';
import 'package:uz_ai_dev/yuk/ui/yuk_home_ui.dart';
import 'package:uz_ai_dev/user/services/info_piuls.dart';
import 'package:uz_ai_dev/user/ui/user_home_ui.dart';
import 'dart:convert';
import 'user/services/api_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? version;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    getAppVersion().then((v) {
      if (mounted) setState(() => version = v);
    });
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    // v1 login — FAQAT parol bilan kiriladi (telefon so'ralmaydi).
    final result = await ApiService.loginV1(_passwordController.text);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });

    if (result['success'] == true) {
      TextInput.finishAutofillContext();

      // Server javobida data/token/user bo'lmasa — throw emas, xato dialogi.
      final data = result['data'];
      final token = data is Map ? data['token'] : null;
      final rawUser = data is Map ? data['user'] : null;
      if (token is! String || rawUser is! Map) {
        _showErrorDialog(result['message'] ?? 'Login xatosi');
        return;
      }
      final user = Map<String, dynamic>.from(rawUser);

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token);
      // Nomni JSON qo'shtirnoqsiz, toza matn sifatida saqlaymiz.
      await prefs.setString('name', (user["name"] ?? '').toString());
      await prefs.setBool("is_admin", user["is_admin"] ?? false);
      await prefs.setString("role", user["role"] ?? AppRoles.seller);
      await prefs.setString('user', jsonEncode(user));

      // Sklad nomlarini serverdan olib qo'yamiz (tab/dropdown shulardan
      // quriladi). Xato bo'lsa keshdagi/default nomlar qoladi.
      await SkladRegistry.refreshSilently();

      if (!mounted) return;
      // Ombor 2.0 (mone_core): o'sha kod bilan fonda kiramiz — kutmaymiz,
      // xato bo'lsa «Ombor 2.0» bo'limi «ulanmagan» ko'rsatadi.
      unawaited(
          context.read<CoreSession>().loginWithCode(_passwordController.text));
      _navigateByRole(user);
    } else {
      _showErrorDialog(result['message'] ?? 'Login xatosi');
    }
  }

  Future<void> _navigateByRole(Map<String, dynamic> user) async {
    final role = user["role"] ?? AppRoles.seller;
    final isAdmin = user["is_admin"] ?? false;

    if (isAdmin == true || role == AppRoles.superAdmin) {
      context.pushAndRemove(const AdminHomeUi());
    } else if (role == AppRoles.ombor) {
      context.pushAndRemove(const OmborHomeUi());
    } else if (role == AppRoles.yukKeltiruvchi) {
      context.pushAndRemove(const YukHomeUi());
    } else if (role == AppRoles.bugalter) {
      context.pushAndRemove(const BugalterHomeUi());
    } else if (role == AppRoles.shef) {
      context.pushAndRemove(const ShefHomeUi());
    } else if (role == "customer" || role == "bringer") {
      // Bu rollar hozircha qo'llab-quvvatlanmaydi
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      if (!mounted) return;
      _showErrorDialog('Bu rol qo\'llab-quvvatlanmaydi');
    } else {
      context.pushAndRemove(const UserHomeUi());
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 10),
            Text('error'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: Card(
              elevation: 15,
              shadowColor: Colors.blue.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: EdgeInsets.all(30),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person,
                            size: 40,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        SizedBox(height: 20),
                        Text(
                          "Login",
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade800,
                          ),
                        ),
                        SizedBox(height: 30),
                        // v1 login: FAQAT parol so'raladi (HR ilovasidagi kabi).
                        TextFormField(
                          controller: _passwordController,
                          keyboardType: TextInputType.visiblePassword,
                          autofillHints: const [AutofillHints.password],
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Parol',
                            prefixIcon: Icon(Icons.lock, color: Colors.blue),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: Colors.blue,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: Colors.blue, width: 2),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'enter_password';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 5,
                            ),
                            child: _isLoading
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Text('wait'),
                                    ],
                                  )
                                : Text(
                                    'Login',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        SizedBox(height: 20),
                        Text(version ?? ""),
                        const SizedBox(height: 6),
                        // Server manzillari (v1/v2) — «localhost» / IP / domen.
                        ValueListenableBuilder<int>(
                          valueListenable: ServerConfig.revision,
                          builder: (context, _, __) => TextButton.icon(
                            onPressed: () => showServerSettingsDialog(context),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.grey.shade600),
                            icon: const Icon(Icons.settings_outlined, size: 16),
                            label: Text(
                              _shortHost(ServerConfig.baseUrl),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // «https://moneapp.monebakeryuz.uz» → «moneapp.monebakeryuz.uz».
  static String _shortHost(String url) =>
      url.replaceFirst(RegExp(r'^https?://'), '');

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }
}
