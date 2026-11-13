import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../widgets/admin_form.dart';
import '../widgets/admin_page.dart';
import '../widgets/admin_widgets.dart';

/// Bulut sozlamalari — WSS bulut serveriga ulanish (super_admin)
class CloudSettingsScreen extends StatefulWidget {
  const CloudSettingsScreen({super.key});
  @override
  State<CloudSettingsScreen> createState() => _CloudSettingsScreenState();
}

class _CloudSettingsScreenState extends State<CloudSettingsScreen> {
  final TextEditingController _urlC = TextEditingController();
  final TextEditingController _tokenC = TextEditingController();
  bool _connected = false;
  bool _loading = true;
  bool _saving = false;
  /// Yuklash yiqildi — saqlash bloklanadi (sozlamani o'chirib yubormaslik uchun).
  bool _loadFailed = false;
  bool _tokenHidden = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlC.dispose();
    _tokenC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().getCloudSettings();
      if (mounted) {
        setState(() {
          _urlC.text = (res['url'] ?? '').toString();
          _tokenC.text = (res['token'] ?? '').toString();
          _connected = res['connected'] == true;
          _loading = false;
        });
      }
    } catch (_) {
      // Xato JIMGINA yutilmaydi.
      //
      // Ilgari yuklash yiqilsa forma BO'SH holda ochilardi va sync
      // sozlanmagandek ko'rinardi. Super_admin "yo'qolibdi" deb o'ylab
      // hech narsa kiritmasdan "Saqlash"ni bossa — server ikkala qiymatni
      // ham BO'SH qilib yozardi va butun restoran uchun local↔cloud sync
      // o'chib qolardi, tokenni tiklashning esa iloji yo'q edi.
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_loadFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Sozlama yuklanmagan — saqlash bloklandi. Avval qayta yuklang.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    final url = _urlC.text.trim();
    if (url.isNotEmpty &&
        !url.startsWith('ws://') &&
        !url.startsWith('wss://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('URL ws:// yoki wss:// bilan boshlanishi kerak'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiService().setCloudSettings(url, _tokenC.text.trim());
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Saqlandi'),
            backgroundColor: AppColors.success),
      );
      // Ulanish holatini yangilash
      await Future.delayed(const Duration(seconds: 1));
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      String msg = 'Saqlab bo\'lmadi';
      if (e is DioException && e.response?.data is Map) {
        final m = (e.response!.data as Map);
        msg = (m['message'] ?? m['error'] ?? msg).toString();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      subtitle: _connected ? 'Bulut bilan aloqa bor' : 'Bulutga ulanmagan',
      loading: _loading,
      onRefresh: _load,
      constrained: true,
      child: ListView(
        padding: const EdgeInsets.only(top: 14, bottom: 28),
        children: [
          AdminSection(
            title: 'Bulut serveri',
            subtitle: 'Local baza shu server bilan sinxronlanadi',
            icon: Icons.cloud_rounded,
            color: AppColors.info,
            trailing: StatusBadge(
              label: _connected ? 'Ulangan' : 'Ulanmagan',
              color: _connected ? AppColors.success : AppColors.danger,
              icon: _connected
                  ? Icons.check_circle_rounded
                  : Icons.error_outline_rounded,
            ),
            children: [
              AdminField(
                label: 'Server manzili',
                controller: _urlC,
                // Cloud peer endpoint'i — `/sync` (internal/api/router.go:231),
                // `/ws` emas: `/ws` POS terminallari uchun.
                hint: 'wss://konak.uzaidev.uz/sync',
                icon: Icons.link_rounded,
                keyboardType: TextInputType.url,
              ),
              // Token — butun bazaga yozish huquqini beradigan umumiy sir.
              // Ilgari ochiq matnda ko'rinardi: zal planshetida ekran
              // ochilgan zahoti uni yonidagi har kim o'qib qo'ya olardi.
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6, left: 2),
                      child: Row(
                        children: [
                          Icon(Icons.key_rounded,
                              size: 14, color: AppColors.textFaint),
                          SizedBox(width: 6),
                          Text(
                            'Sinxronizatsiya tokeni',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextField(
                      controller: _tokenC,
                      obscureText: _tokenHidden,
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 15),
                        suffixIcon: IconButton(
                          tooltip: _tokenHidden ? 'Ko‘rsatish' : 'Yashirish',
                          icon: Icon(_tokenHidden
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded),
                          onPressed: () =>
                              setState(() => _tokenHidden = !_tokenHidden),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.infoTint,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.infoSoft),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 18, color: AppColors.info),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Bo‘sh qoldirilsa server faqat local rejimda '
                        'ishlaydi — internetsiz ham savdo davom etadi.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textMuted,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded, size: 20),
                  label: Text(
                    _saving ? 'Saqlanmoqda…' : 'Saqlash',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
