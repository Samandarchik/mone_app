import '../../../core/services/mone_mode.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../../../core/widgets/media_image.dart';
import 'recipe_edit_screen.dart';

class ProductEditScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  final List<dynamic> categories;
  final int? stock;

  /// Yandex Eda sozlamasi — `/api/menu` javobidagi `yandex` bloki:
  /// `{enabled, markup_percent, round_step}`. Berilmasa server bilan bir xil
  /// standart qiymatlar ishlatiladi (15% ustama, 1000 ga yaxlitlash).
  final Map<String, dynamic>? yandex;

  const ProductEditScreen({
    super.key,
    required this.product,
    required this.categories,
    this.stock,
    this.yandex,
  });

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  late TextEditingController _nameUzC, _nameRuC, _nameTrC;
  late TextEditingController _descUzC, _descRuC, _descTrC;
  late TextEditingController _priceC, _oldPriceC;
  late int _selectedCatId;
  late bool _isRecommended;
  late String _status;
  // cooked = tayyorlanadi | ready = tayyor keladi | made = buyurtmaga tayyorlanadi
  late String _productType;
  String? _pickedImagePath;
  bool _saving = false;
  int? _liveCount; // kirimdan keyingi yangi qoldiq (widget.stock eskirganda)

  // ---- Yandex Eda ----
  // `_yaPriceC` bo'sh bo'lsa narx AVTO: POS narxi + ustama, yaxlitlangan.
  // Serverdagi qoida bilan bir xil (internal/api/yandex.go).
  late bool _yaEnabled;
  late TextEditingController _yaPriceC, _yaMxikC, _yaMeasureC;
  late String _yaUnit;
  bool _yaBusy = false;

  /// Ichkaridagi retsept bo'limiga murojaat — oynadan chiqishdan oldin
  /// kiritilgan masalliqlar serverga yuborilishi uchun.
  final GlobalKey<RecipeEditScreenState> _recipeKey = GlobalKey();

  static const _phoneBreakpoint = 720.0;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameUzC = TextEditingController(text: p['name']?['uz'] ?? '');
    _nameRuC = TextEditingController(text: p['name']?['ru'] ?? '');
    _nameTrC = TextEditingController(text: p['name']?['tr'] ?? '');
    _descUzC = TextEditingController(text: p['description']?['uz'] ?? '');
    _descRuC = TextEditingController(text: p['description']?['ru'] ?? '');
    _descTrC = TextEditingController(text: p['description']?['tr'] ?? '');
    // formatMoney: maydonlar MoneyInputFormatter bilan "25 000" ko'rinishida
    // yuritiladi — boshlang'ich qiymat ham shu formatda ochilsin.
    _priceC = TextEditingController(text: formatMoney(p['price'] ?? 0));
    _oldPriceC = TextEditingController(
      text: p['old_price'] != null ? formatMoney(p['old_price']) : '',
    );
    _selectedCatId = p['category_id'] ?? 0;
    _isRecommended = p['is_recommended'] == true;
    _status = p['status'] ?? 'active';
    _productType = _normalizeType(p['product_type']);

    _yaEnabled = p['yandex_enabled'] == true;
    final yaPrice = p['yandex_price'];
    _yaPriceC = TextEditingController(
      text: (yaPrice is int && yaPrice > 0) ? formatMoney(yaPrice) : '',
    );
    _yaMxikC = TextEditingController(text: p['yandex_mxik']?.toString() ?? '');
    final meas = p['yandex_measure'];
    _yaMeasureC = TextEditingController(
      text: (meas is int && meas > 0) ? meas.toString() : '',
    );
    _yaUnit = _normalizeUnit(p['yandex_measure_unit']?.toString());
    // Avto narx POS narxidan hisoblanadi — narx yozilayotganda darhol
    // yangilanib tursin (admin qancha chiqishini ko'rib turadi).
    _priceC.addListener(_onPriceChanged);
  }

  void _onPriceChanged() {
    if (_yaEnabled && mounted) setState(() {});
  }

  static String _normalizeUnit(String? v) {
    const allowed = ['г', 'мл', 'шт'];
    return allowed.contains(v) ? v! : 'г';
  }

  // ---- Yandex narxi ----
  // AYNAN serverdagi qoida (internal/api/yandex.go: yandexAutoPrice):
  // ustama qo'shiladi, eng yaqin qadamga yaxlitlanadi, lekin natija POS
  // narxidan past (yoki ustama bo'lsa — teng) bo'lib qolmaydi.
  int get _yaMarkup => (widget.yandex?['markup_percent'] as int?) ?? 15;
  int get _yaRoundStep {
    final v = widget.yandex?['round_step'] as int?;
    return (v == null || v < 1) ? 1000 : v;
  }

  int _yaAutoPrice(int base) {
    if (base <= 0) return 0;
    final step = _yaRoundStep;
    final markup = _yaMarkup;
    final withMarkup = base * (1 + markup / 100);
    var price = (withMarkup / step).round() * step;
    if (price < base || (markup > 0 && price <= base)) {
      price = (withMarkup / step).ceil() * step;
    }
    return price <= 0 ? step : price;
  }

  /// Yandexda AYNAN turadigan narx (qo'lda berilgan bo'lsa o'sha).
  int get _yaFinalPrice {
    final manual = _parseMoney(_yaPriceC.text);
    if (manual != null && manual > 0) return manual;
    return _yaAutoPrice(_parseMoney(_priceC.text) ?? 0);
  }

  String _getImage() {
    final media = widget.product['media'];
    if (media is List && media.isNotEmpty) return media[0]['url'] ?? '';
    return '';
  }

  bool get _isNew => (widget.product['id'] as int? ?? 0) == 0;

  /// Pul maydonini o'qish — bo'sh joy va ajratgichlarga chidamli.
  /// Ilova narxlarni "25 000" ko'rinishida ko'rsatgani uchun admin ham
  /// shunday yozadi; `int.tryParse` esa bunda null qaytarib, narx jimgina
  /// yuborilmay qolardi.
  static int? _parseMoney(String raw) {
    final cleaned = raw.replaceAll(RegExp(r"[\s\u00A0']"), '');
    if (cleaned.isEmpty) return null;
    if (!RegExp(r'^[0-9]+$').hasMatch(cleaned)) return null;
    return int.tryParse(cleaned);
  }

  /// Retsept bo'limida yozilgan, lekin hali yuborilmagan o'zgarishlarni
  /// serverga jo'natadi. Oynadan chiqishdan oldin doim chaqiriladi —
  /// "Retseptni saqlash" bosish esdan chiqsa ham hech narsa yo'qolmaydi.
  Future<void> _flushRecipe() async {
    try {
      await _recipeKey.currentState?.flushPendingSave();
    } catch (_) {}
  }

  Future<void> _closeScreen([bool changed = false]) async {
    await _flushRecipe();
    if (mounted) Navigator.pop(context, changed);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _flushRecipe();
    final p = widget.product;
    final data = <String, dynamic>{};

    if (_nameUzC.text != (p['name']?['uz'] ?? '')) {
      data['name_uz'] = _nameUzC.text;
    }
    if (_nameRuC.text != (p['name']?['ru'] ?? '')) {
      data['name_ru'] = _nameRuC.text;
    }
    if (_nameTrC.text != (p['name']?['tr'] ?? '')) {
      data['name_tr'] = _nameTrC.text;
    }
    if (_descUzC.text != (p['description']?['uz'] ?? '')) {
      data['description_uz'] = _descUzC.text;
    }
    if (_descRuC.text != (p['description']?['ru'] ?? '')) {
      data['description_ru'] = _descRuC.text;
    }
    if (_descTrC.text != (p['description']?['tr'] ?? '')) {
      data['description_tr'] = _descTrC.text;
    }
    // NARX — eng xavfli maydon.
    //
    // Ilgari `int.tryParse` null qaytarsa narx JIMGINA yuborilmasdi va
    // saqlash "muvaffaqiyatli" ko'rinardi. Admin narxni "25 000" deb
    // yozadi (ilovaning o'zi narxlarni shu ko'rinishda ko'rsatadi), eski
    // narx esa POS'da qolib ketardi — kun bo'yi eski narxda sotilardi.
    final newPrice = _parseMoney(_priceC.text);
    if (_priceC.text.trim().isNotEmpty && newPrice == null) {
      throw "Narx faqat raqamdan iborat bo'lishi kerak";
    }
    if (newPrice != null) {
      if (newPrice <= 0) {
        // 0 narx POS'da ham, QR menyuda ham tekin sotuvga olib kelardi.
        throw "Narx 0 dan katta bo'lishi kerak";
      }
      if (newPrice != p['price']) data['price'] = newPrice;
    }
    if (_oldPriceC.text.trim().isEmpty) {
      // Chegirmani OLIB TASHLASH: server `*int` ishlatgani uchun JSON null
      // "yuborilmadi" degani edi va eski narx hech qachon o'chmasdi —
      // aksiya tugagach ham menyuda chizilgan narx turaverardi.
      // 0 — serverda NULL ga aylantiriladigan kelishilgan qiymat.
      if (p['old_price'] != null) data['old_price'] = 0;
    } else {
      final op = _parseMoney(_oldPriceC.text);
      if (op == null) {
        throw "Eski narx faqat raqamdan iborat bo'lishi kerak";
      }
      data['old_price'] = op;
    }
    if (_selectedCatId != p['category_id']) {
      data['category_id'] = _selectedCatId;
    }
    if (_status != p['status']) data['status'] = _status;
    if (_isRecommended != (p['is_recommended'] == true)) {
      data['is_recommended'] = _isRecommended;
    }
    if (_productType != (p['product_type'] ?? 'cooked')) {
      data['product_type'] = _productType;
    }
    data.addAll(_yandexPayload(p));

    try {
      int productId = p['id'] as int;
      final wasNew = productId == 0;
      if (productId == 0) {
        if (_nameUzC.text.trim().isEmpty) {
          throw 'Mahsulot nomi kiritilishi shart';
        }
        if (newPrice == null || newPrice <= 0) {
          throw 'Narx kiritilishi shart';
        }
        data['name_uz'] = _nameUzC.text.trim();
        data['name_ru'] = _nameRuC.text.trim();
        data['name_tr'] = _nameTrC.text.trim();
        data['description_uz'] = _descUzC.text.trim();
        data['description_ru'] = _descRuC.text.trim();
        data['description_tr'] = _descTrC.text.trim();
        data['price'] = newPrice;
        data['category_id'] = _selectedCatId;
        data['status'] = _status;
        data['is_recommended'] = _isRecommended;
        data['product_type'] = _productType;
        data['yandex_enabled'] = _yaEnabled;
        final res = await ApiService().createProduct(data);
        productId = res['id'] as int;
        // `POST /api/product` faqat `yandex_enabled` ni oladi — qolgan
        // Yandex maydonlari (narx, ИКПУ, og'irlik) alohida yuboriladi.
        final yaExtra = _yandexPayload(const {})
          ..remove('yandex_enabled');
        if (yaExtra.isNotEmpty) {
          await ApiService().updateProduct(productId, yaExtra);
        }
        // Id ni widget'ga qaytaramiz: keyingi qadam (rasm yuklash) xato bersa,
        // qayta "Saqlash" bosilganda YANGI mahsulot emas, shu mahsulot
        // yangilanadi. Ilgari menyuda ikkita bir xil taom paydo bo'lardi.
        widget.product['id'] = productId;
      } else {
        if (data.isNotEmpty) {
          await ApiService().updateProduct(productId, data);
        }
      }
      if (_pickedImagePath != null) {
        await ApiService().uploadProductImage(productId, _pickedImagePath!);
      }
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      // Yangi "Tayyorlanadi" mahsulot — darhol retsept kiritishga o'tamiz
      if (wasNew && _hasRecipe) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Mahsulot yaratildi — endi ichidagi masalliqlarini kiriting'),
          backgroundColor: AppColors.success,
        ));
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RecipeEditScreen(
              productId: productId,
              productName: _nameUzC.text.trim(),
            ),
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Xato: $e'),
              backgroundColor: AppColors.danger),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('O\'chirish'),
        content:
            const Text('Mahsulotni o\'chirishni xohlaysizmi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Yo\'q')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Ha, o\'chirish'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        // O'chirilayotgan mahsulotga retsept qaytib yozilmasin.
        _recipeKey.currentState?.cancelPendingSave();
        await ApiService().deleteProduct(widget.product['id']);
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Xato: $e'),
                backgroundColor: AppColors.danger),
          );
        }
      }
    }
  }

  Future<void> _pickImageFrom(ImageSource source) async {
    final path = await pickImagePath(source: source);
    if (path != null && mounted) {
      setState(() => _pickedImagePath = path);
    }
  }

  void _showImageSheet() {
    final isMobile = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;

    // Desktopda kamera yo'q — to'g'ridan-to'g'ri galereya
    if (!isMobile) {
      _pickImageFrom(ImageSource.gallery);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Rasm tanlang',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              _sheetTile(
                Icons.photo_library_rounded,
                'Galereyadan tanlash',
                AppColors.primary,
                () {
                  Navigator.pop(ctx);
                  _pickImageFrom(ImageSource.gallery);
                },
              ),
              _sheetTile(
                Icons.camera_alt_rounded,
                'Kameradan suratga olish',
                AppColors.success,
                () {
                  Navigator.pop(ctx);
                  _pickImageFrom(ImageSource.camera);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetTile(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            IconAvatar(icon: icon, color: color, size: 40),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < _phoneBreakpoint;
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            toolbarHeight: 64,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  // Ortga bosilganda ham retsept saqlanadi.
                  onTap: () => _closeScreen(),
                  child: const Icon(Icons.arrow_back_rounded, size: 22),
                ),
              ),
            ),
            title: Text(
              _isNew
                  ? 'Yangi mahsulot'
                  : (_nameUzC.text.isEmpty
                      ? 'Mahsulot'
                      : _nameUzC.text),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (!_isNew)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Material(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: _confirmDelete,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.delete_outline_rounded,
                            color: AppColors.danger, size: 22),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: isPhone ? _buildPhoneLayout() : _buildDesktopLayout(),
          // Saqlash tugmasi har doim pastda — sticky
          bottomNavigationBar: _buildSaveBar(),
        );
      },
    );
  }

  Widget _buildSaveBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
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
          label: Text(
            _saving
                ? 'Saqlanmoqda...'
                : (_isNew ? 'Yaratish' : 'Saqlash'),
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
          ),
        ),
      ),
    );
  }

  // ===== PHONE LAYOUT =====
  Widget _buildPhoneLayout() {
    return ListView(
      // Ro'yxatni surish klaviaturani yopadi: raqamli klaviaturada iOS
      // "Tayyor" tugmasini ko'rsatmaydi, aks holda uni yopib bo'lmasdi.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      // Telefonda chekka va oraliqlar ixcham — ekran kichkina, har bir
      // piksel ma'lumot uchun kerak.
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      children: [
        _imageBlock(),
        const SizedBox(height: 10),
        _statusBlock(),
        const SizedBox(height: 10),
        _namesBlock(),
        const SizedBox(height: 10),
        _descBlock(),
        const SizedBox(height: 10),
        _categoryBlock(),
        const SizedBox(height: 10),
        _priceBlock(),
        const SizedBox(height: 10),
        _typeBlock(),
        const SizedBox(height: 10),
        _yandexBlock(),
        const SizedBox(height: 10),
        _stockBlock(),
        if (_hasRecipe) ...[
          const SizedBox(height: 10),
          _recipeBlock(),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  // ===== DESKTOP LAYOUT =====
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        SizedBox(
          width: 280,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _imageBlock(),
              const SizedBox(height: 12),
              _statusBlock(),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _namesBlock(),
              const SizedBox(height: 12),
              _descBlock(),
              const SizedBox(height: 12),
              _categoryBlock(),
              const SizedBox(height: 12),
              _priceBlock(),
              const SizedBox(height: 12),
              _typeBlock(),
              const SizedBox(height: 12),
              _yandexBlock(),
              const SizedBox(height: 12),
              _stockBlock(),
              if (_hasRecipe) ...[
                const SizedBox(height: 12),
                _recipeBlock(),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  // ===== Blocks =====

  Widget _imageBlock() {
    final currentImage = _getImage();
    final hasImage =
        _pickedImagePath != null || currentImage.isNotEmpty;
    return _Card(
      title: 'Rasm',
      icon: Icons.image_rounded,
      child: Column(
        children: [
          GestureDetector(
            onTap: _showImageSheet,
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: hasImage
                        ? AppColors.border
                        : AppColors.primary.withValues(alpha: 0.3),
                    width: hasImage ? 1 : 1.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _pickedImagePath != null
                    ? Image.file(File(_pickedImagePath!),
                        fit: BoxFit.cover)
                    : currentImage.isNotEmpty
                        ? MediaImage(
                            path: currentImage,
                            placeholder: const _ImagePlaceholder(),
                          )
                        : const _ImagePlaceholder(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _showImageSheet,
              icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
              label: Text(
                  hasImage ? 'Rasmni o\'zgartirish' : 'Rasm qo\'shish'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBlock() {
    return _Card(
      title: 'Holat',
      icon: Icons.tune_rounded,
      child: Column(
        children: [
          _toggleRow(
            label: _status == 'active' ? 'Aktiv' : 'Nofaol',
            sub: _status == 'active'
                ? 'Mahsulot menyu da ko\'rinadi'
                : 'Mahsulot yashirin',
            value: _status == 'active',
            color: _status == 'active' ? AppColors.success : AppColors.danger,
            icon: _status == 'active'
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
            onChanged: (v) =>
                setState(() => _status = v ? 'active' : 'inactive'),
          ),
          const Divider(height: 16, color: AppColors.borderSoft),
          _toggleRow(
            label: 'Tavsiya etiladi',
            sub: 'Bosh sahifa va POS da yorqin ko\'rsatiladi',
            value: _isRecommended,
            color: AppColors.warning,
            icon: Icons.star_rounded,
            onChanged: (v) => setState(() => _isRecommended = v),
          ),
        ],
      ),
    );
  }

  /// Telefon uchun ixcham matn maydoni — mavzudagi 14/14 chekka uch-to'rt
  /// maydon yonma-yon kelganda ekranni yeb qo'yardi.
  static const _denseField =
      EdgeInsets.symmetric(horizontal: 12, vertical: 11);

  Widget _toggleRow({
    required String label,
    required String sub,
    required bool value,
    required Color color,
    required IconData icon,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        IconAvatar(icon: icon, color: color, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              Text(sub,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: color,
        ),
      ],
    );
  }

  Widget _namesBlock() {
    return _Card(
      title: 'Mahsulot nomi',
      icon: Icons.title_rounded,
      child: Column(
        children: [
          if (_moneLocked) _moneNote(),
          _field(_nameUzC, 'O\'zbekcha', flag: '🇺🇿', readOnly: _moneLocked),
          _field(_nameRuC, 'Ruscha', flag: '🇷🇺', readOnly: _moneLocked),
          _field(_nameTrC, 'Turkcha', flag: '🇹🇷', last: true, readOnly: _moneLocked),
        ],
      ),
    );
  }

  Widget _descBlock() {
    return _Card(
      title: 'Tavsif',
      icon: Icons.notes_rounded,
      child: Column(
        children: [
          _field(_descUzC, 'O\'zbekcha', flag: '🇺🇿', maxLines: 2),
          _field(_descRuC, 'Ruscha', flag: '🇷🇺', maxLines: 2),
          _field(_descTrC, 'Turkcha',
              flag: '🇹🇷', maxLines: 2, last: true),
        ],
      ),
    );
  }

  Widget _categoryBlock() {
    return _Card(
      title: 'Kategoriya',
      icon: Icons.folder_rounded,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _selectedCatId == 0 ? null : _selectedCatId,
            isExpanded: true,
            hint: const Text('Kategoriya tanlang'),
            icon: const Icon(Icons.expand_more_rounded),
            borderRadius: BorderRadius.circular(AppRadius.md),
            items: widget.categories
                .map((c) => DropdownMenuItem<int>(
                      value: c['id'] as int,
                      child: Text(c['name']?['uz'] ?? ''),
                    ))
                .toList(),
            onChanged: _moneLocked
                ? null
                : (v) {
                    if (v != null) setState(() => _selectedCatId = v);
                  },
          ),
        ),
      ),
    );
  }

  Widget _priceBlock() {
    return _Card(
      title: 'Narx',
      icon: Icons.payments_rounded,
      child: Column(
        children: [
          if (_moneLocked) _moneNote(),
          TextField(
            controller: _priceC,
            readOnly: _moneLocked,
            enabled: !_moneLocked,
            decoration: const InputDecoration(
              labelText: 'Narx',
              suffixText: 'so\'m',
              contentPadding: _denseField,
              prefixIcon: Icon(Icons.attach_money_rounded,
                  color: AppColors.success),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: const [MoneyInputFormatter()],
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _oldPriceC,
            decoration: const InputDecoration(
              labelText: 'Eski narx (chegirma uchun)',
              suffixText: 'so\'m',
              contentPadding: _denseField,
              prefixIcon: Icon(Icons.local_offer_rounded,
                  color: AppColors.textMuted),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: const [MoneyInputFormatter()],
          ),
        ],
      ),
    );
  }

  // ===== YANDEX EDA =====
  //
  // Yandex menyuni O'ZI tortadi (pull-model, odatda 15 daqiqada bir), shuning
  // uchun bu yerdagi tugma mahsulotni "yubormaydi" — CHIQARILADIGAN qilib
  // BELGILAYDI. Yandex keyingi tortishda oladi.
  //
  // Narx POS narxi emas: ustama qo'shilib eng yaqin 1000 ga yaxlitlanadi
  // (35 000 → 40 000, 38 000 → 44 000). Qoida serverda ham, shu yerda ham
  // bir xil — admin qancha chiqishini yozayotgan paytda ko'rib turadi.

  /// Serverga yuboriladigan Yandex maydonlari (faqat O'ZGARGANLARI).
  /// `old` — mahsulotning avvalgi holati; bo'sh map berilsa hamma qiymat
  /// yangi hisoblanadi (yangi mahsulot yaratilganda).
  Map<String, dynamic> _yandexPayload(Map<String, dynamic> old) {
    final data = <String, dynamic>{};
    if (_yaEnabled != (old['yandex_enabled'] == true)) {
      data['yandex_enabled'] = _yaEnabled;
    }
    // Qo'lda narx: bo'sh maydon = AVTO. Serverda 0 — "avto narxga qaytar"
    // degani (JSON null "yuborilmadi" bo'lib tushuniladi).
    final manual = _parseMoney(_yaPriceC.text) ?? 0;
    final oldManual = (old['yandex_price'] is int) ? old['yandex_price'] as int : 0;
    if (manual != oldManual) data['yandex_price'] = manual;

    final mxik = _yaMxikC.text.trim();
    if (mxik != (old['yandex_mxik']?.toString() ?? '')) data['yandex_mxik'] = mxik;

    final measure = int.tryParse(_yaMeasureC.text.trim()) ?? 0;
    final oldMeasure = (old['yandex_measure'] is int) ? old['yandex_measure'] as int : 0;
    if (measure != oldMeasure) data['yandex_measure'] = measure;

    if (_yaUnit != _normalizeUnit(old['yandex_measure_unit']?.toString())) {
      data['yandex_measure_unit'] = _yaUnit;
    }
    return data;
  }

  /// Yandexga chiqishga nimasi yetishmayapti. Bloklamaydi — ogohlantiradi.
  List<String> get _yaWarnings {
    final w = <String>[];
    if (_nameRuC.text.trim().isEmpty) {
      w.add('Ruscha nom yo\'q — Yandexga o\'zbekcha nom chiqadi');
    }
    if (_descRuC.text.trim().isEmpty) w.add('Ruscha tavsif yo\'q');
    if (_pickedImagePath == null && _getImage().isEmpty) {
      w.add('Rasm yo\'q — Yandex rasmsiz taomni ko\'rsatmaydi');
    }
    if ((_parseMoney(_priceC.text) ?? 0) <= 0) w.add('Narx kiritilmagan');
    return w;
  }

  /// Yandex tugmasi. MAVJUD mahsulotda darhol qo'llanadi — «Saqlash»ni
  /// kutmaydi: admin tugmani bosgan zahoti mahsulot Yandex menyusiga
  /// belgilanadi va javobda qaysi narxda turishi ko'rsatiladi.
  ///
  /// Yangi (hali yaratilmagan) mahsulotda esa faqat belgilab qo'yiladi —
  /// mahsulot id'si yo'q, u «Yaratish» bilan birga yuboriladi.
  Future<void> _toggleYandex(bool v) async {
    final id = widget.product['id'] as int? ?? 0;
    setState(() => _yaEnabled = v);
    if (id == 0) return;

    setState(() => _yaBusy = true);
    try {
      final res = await ApiService().setProductYandex(id, {'enabled': v});
      // Endi bu qiymat serverda — «Saqlash» uni qayta yubormasin.
      widget.product['yandex_enabled'] = v;
      if (!mounted) return;
      final price = res['yandex_price'];
      final warnings = (res['warnings'] as List<dynamic>? ?? []).cast<String>();
      final msg = v
          ? 'Yandexga chiqarildi — narxi ${formatMoney(price ?? 0)} so\'m'
          : 'Yandex menyusidan olib tashlandi';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          warnings.isEmpty ? msg : '$msg\n\u26a0 ${warnings.join('; ')}',
        ),
        backgroundColor: v ? AppColors.success : AppColors.textMuted,
        duration: Duration(seconds: warnings.isEmpty ? 3 : 6),
      ));
    } catch (e) {
      if (mounted) {
        // Server qabul qilmadi — tugmani orqaga qaytaramiz, aks holda
        // ekranda "chiqarilgan" ko'rinib, aslida chiqmagan bo'lardi.
        setState(() => _yaEnabled = !v);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Xato: $e'),
          backgroundColor: AppColors.danger,
        ));
      }
    }
    if (mounted) setState(() => _yaBusy = false);
  }

  Widget _yandexBlock() {
    final base = _parseMoney(_priceC.text) ?? 0;
    final auto = _yaAutoPrice(base);
    final manual = _parseMoney(_yaPriceC.text) ?? 0;
    final isManual = manual > 0;
    final integrationOff = widget.yandex != null && widget.yandex!['enabled'] != true;

    return _Card(
      title: 'Yandex Eda',
      icon: Icons.delivery_dining_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _toggleRow(
            label: 'Yandexga chiqarish',
            sub: _yaEnabled
                ? 'Yandex menyusida ko\'rinadi (Yandex o\'zi yangilab oladi)'
                : 'Yandex menyusiga chiqmaydi',
            value: _yaEnabled,
            color: kYandexColor,
            icon: Icons.delivery_dining_rounded,
            // Server javobi kelguncha ikkinchi bosishni o'tkazmaymiz —
            // aks holda ikkita qarama-qarshi so'rov ketardi.
            onChanged: (v) {
              if (!_yaBusy) _toggleYandex(v);
            },
          ),
          if (_yaEnabled) ...[
            const SizedBox(height: 12),
            _yaPriceBanner(base: base, auto: auto, isManual: isManual),
            const SizedBox(height: 10),
            TextField(
              controller: _yaPriceC,
              decoration: InputDecoration(
                labelText: 'Yandex narxi (bo\'sh = avto)',
                suffixText: 'so\'m',
                contentPadding: _denseField,
                prefixIcon: const Icon(Icons.edit_rounded,
                    color: AppColors.textMuted),
                helperText: isManual
                    ? 'Qo\'lda qo\'yilgan narx — avto hisob ishlatilmaydi'
                    : 'Bo\'sh qoldirsangiz narx avtomatik hisoblanadi',
                helperMaxLines: 2,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: const [MoneyInputFormatter()],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            // ИКПУ — O'zbekistonda MAJBURIY. Bo'sh bo'lsa server sozlamasidagi
            // umumiy kod ketadi; kodsiz Yandex tovarni filtrlab tashlaydi.
            TextField(
              controller: _yaMxikC,
              decoration: const InputDecoration(
                labelText: 'ИКПУ (MXIK) kodi',
                contentPadding: _denseField,
                prefixIcon: Icon(Icons.qr_code_2_rounded,
                    color: AppColors.textMuted),
                helperText: 'Bo\'sh bo\'lsa server sozlamasidagi umumiy kod ketadi',
                helperMaxLines: 2,
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _yaMeasureC,
                    decoration: const InputDecoration(
                      labelText: 'Og\'irligi / hajmi',
                      contentPadding: _denseField,
                      prefixIcon: Icon(Icons.scale_rounded,
                          color: AppColors.textMuted),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _yaUnit,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        items: const [
                          DropdownMenuItem(value: 'г', child: Text('г')),
                          DropdownMenuItem(value: 'мл', child: Text('мл')),
                          DropdownMenuItem(value: 'шт', child: Text('шт')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _yaUnit = v);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_yaWarnings.isNotEmpty) ...[
              const SizedBox(height: 10),
              ..._yaWarnings.map((w) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 15, color: AppColors.warning),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(w,
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textMuted)),
                        ),
                      ],
                    ),
                  )),
            ],
            if (integrationOff) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 15, color: AppColors.info),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Serverda Yandex kalitlari (YANDEX_CLIENT_ID/SECRET) '
                      'kiritilmagan — belgilash saqlanadi, lekin Yandex hali '
                      'menyuni tortmaydi.',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Narx bannerи: POS narxi → ustama → Yandexdagi narx.
  Widget _yaPriceBanner({
    required int base,
    required int auto,
    required bool isManual,
  }) {
    final shown = _yaFinalPrice;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kYandexColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: kYandexColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isManual
                ? 'Yandexda turadigan narx (qo\'lda)'
                : 'Yandexda turadigan narx (avto, +$_yaMarkup%)',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            '${formatMoney(shown)} so\'m',
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: kYandexColor),
          ),
          if (!isManual && base > 0) ...[
            const SizedBox(height: 2),
            Text(
              '${formatMoney(base)} + $_yaMarkup% = '
              '${formatMoney((base * (1 + _yaMarkup / 100)).round())}'
              '  →  $_yaRoundStep ga yaxlitlab ${formatMoney(auto)}',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  static const _types = {'cooked', 'ready', 'made'};

  static String _normalizeType(dynamic v) =>
      v is String && _types.contains(v) ? v : 'cooked';

  /// Retsept kerak bo'ladigan turlar (tayyorlanadi / buyurtmaga tayyorlanadi).
  bool get _hasRecipe => _productType == 'cooked' || _productType == 'made';

  // Mahsulot turi — 3 xil: tayyorlanadi (partiya, retseptli) / tayyor keladi /
  // buyurtmaga tayyorlanadi (retsept bo'yicha masalliqdan hisoblanadi)
  Widget _typeBlock() {
    return _Card(
      title: 'Mahsulot turi',
      icon: Icons.category_rounded,
      child: Column(
        children: [
          _typeOption(
            value: 'made',
            icon: Icons.emoji_food_beverage_rounded,
            color: AppColors.success,
            label: 'Buyurtmaga tayyorlanadi',
            sub: 'Choy, kofe, limonad kabi — har buyurtmada tayyorlanadi. '
                'Retsept bo\'yicha masalliq bo\'lsa sotuvda TURADI, '
                'sotilganda masalliq o\'zi kamayadi, masalliq kirim qilinsa '
                'o\'zi qaytib chiqadi.',
          ),
          const SizedBox(height: 6),
          _typeOption(
            value: 'cooked',
            icon: Icons.bakery_dining_rounded,
            color: AppColors.warning,
            label: 'Tayyorlanadi',
            sub: 'Oshxonada pishiriladi (masalan: tort). Ichidagi masalliqlari '
                '(retsept) kiritilishi SHART — pishirilganda ombordan '
                'masalliqlar avtomatik kamayadi.',
          ),
          const SizedBox(height: 6),
          _typeOption(
            value: 'ready',
            icon: Icons.local_drink_rounded,
            color: AppColors.info,
            label: 'Tayyor keladi',
            sub: 'Sotib olinadi va shundayligicha sotiladi (masalan: Chortoq '
                'suvi). Retsept kerak emas — kelgani Ombor orqali kiritiladi.',
          ),
        ],
      ),
    );
  }

  Widget _typeOption({
    required String value,
    required IconData icon,
    required Color color,
    required String label,
    required String sub,
  }) {
    final selected = _productType == value;
    return InkWell(
      onTap: () => setState(() => _productType = value),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.08) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            IconAvatar(icon: icon, color: color, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: const TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: AppColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? color : AppColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }

  // Qoldiq — hamma mahsulot 0 dan boshlanadi, bazaga qo'shilgandagina sotiladi
  Widget _stockBlock() {
    final count = _liveCount ?? widget.stock ?? 0;
    return _Card(
      title: 'Qoldiq',
      icon: Icons.inventory_2_rounded,
      child: Column(
        children: [
          Row(
            children: [
              IconAvatar(
                icon: count > 0
                    ? Icons.check_circle_rounded
                    : Icons.remove_circle_outline_rounded,
                color: count > 0 ? AppColors.success : AppColors.textMuted,
                size: 38,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        _productType == 'made'
                            ? 'Masalliqdan: $count ta tayyorlash mumkin'
                            : 'Hozir bazada: $count ta',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      _productType == 'made'
                          ? (count > 0
                              ? 'Retsept bo\'yicha masalliqdan hisoblanadi — '
                                  'sotuvda ko\'rinadi, sotilganda masalliq kamayadi.'
                              : '0 ta — sotuvda KO\'RINMAYDI. Retsept kiritilmagan '
                                  'yoki masalliq tugagan: Ombor → kirim qilinsa '
                                  'o\'zi chiqadi.')
                          : count > 0
                          ? 'POS va QR menyuda sotuvda ko\'rinadi'
                          : (_productType == 'cooked'
                              ? '0 ta — sotuvda KO\'RINMAYDI. Pishirilib "Tayyor" '
                                  'bosilganda bazaga qo\'shiladi va sotuvga chiqadi.'
                              : '0 ta — sotuvda KO\'RINMAYDI. Kelgani pastdagi '
                                  '"Kirim qilish" bilan kiritilganda sotuvga chiqadi.'),
                      style: const TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // "Tayyor keladi" mahsulot — kelganini shu yerdan kiritadi
          if (_productType == 'ready' && !_isNew) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _askArrival,
                icon: const Icon(Icons.add_box_rounded, size: 18),
                label: const Text('Kirim qilish (keldi)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.info,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Kirim dialogi — nechta kelganini so'raydi, bazaga QO'SHADI
  Future<void> _askArrival() async {
    final qtyC = TextEditingController();
    final qty = await showDialog<int>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Kirim qilish'),
        content: TextField(
          controller: qtyC,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Nechta keldi?',
            suffixText: 'ta',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Bekor')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(qtyC.text) ?? 0;
              if (n > 0) Navigator.pop(dctx, n);
            },
            child: const Text('Qo\'shish'),
          ),
        ],
      ),
    );
    if (qty == null || !mounted) return;
    try {
      final res = await ApiService()
          .addStock(widget.product['id'] as int, qty);
      if (!mounted) return;
      setState(() => _liveCount = res['count'] as int?);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Bazaga +$qty ta qo\'shildi (jami: ${res['count']})'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Xato: $e'), backgroundColor: AppColors.danger));
      }
    }
  }

  // Retsept — mahsulot ichidagi masalliqlar shu oynaning o'zida kiritiladi
  Widget _recipeBlock() {
    if (_isNew) {
      return _Card(
        title: 'Retsept (ichidagi masalliqlar)',
        icon: Icons.restaurant_menu_rounded,
        child: Row(
          children: [
            const IconAvatar(
                icon: Icons.info_outline_rounded,
                color: AppColors.info,
                size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Avval "Yaratish" tugmasini bosing — retsept kiritish oynasi '
                'avtomatik ochiladi.',
                style: const TextStyle(
                    fontSize: 12, height: 1.4, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      );
    }
    return _Card(
      title: 'Retsept (ichidagi masalliqlar)',
      icon: Icons.restaurant_menu_rounded,
      // Ichida o'z kartalari bor — tashqi chekka minimal.
      padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
      child: RecipeEditScreen(
        key: _recipeKey,
        productId: widget.product['id'] as int,
        productName: _nameUzC.text,
        embedded: true,
      ),
    );
  }

  /// Mone rejimida mahsulot Mone'dan keladi: nom, narx, kategoriya qulf.
  bool get _moneLocked => MoneMode.enabled.value && widget.product['id'] != null && widget.product['id'] != 0;

  Widget _moneNote() => const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.textMuted),
            SizedBox(width: 6),
            Expanded(
              child: Text(MoneMode.lockedHint,
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            ),
          ],
        ),
      );

  Widget _field(
    TextEditingController c,
    String label, {
    String? flag,
    int maxLines = 1,
    bool last = false,
    bool readOnly = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 8),
      child: TextField(
        controller: c,
        readOnly: readOnly,
        enabled: !readOnly,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: flag != null ? '$flag  $label' : label,
          contentPadding: _denseField,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  /// Retsept bo'limi uchun tor chekka — ichida yana kartalar bor, ikki
  /// qavat 16+16 bo'lib maydon behuda ketardi.
  final EdgeInsets? padding;
  const _Card({
    required this.title,
    required this.icon,
    required this.child,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: padding ?? const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Chekka toraytirilgan kartada sarlavha boshqalar bilan bir
            // chiziqda turishi uchun kichik surish.
            padding: EdgeInsets.symmetric(horizontal: padding == null ? 0 : 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceAlt,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo_rounded,
              size: 48, color: AppColors.textFaint),
          SizedBox(height: 8),
          Text('Rasm qo\'shish uchun bosing',
              style:
                  TextStyle(color: AppColors.textFaint, fontSize: 12)),
        ],
      ),
    );
  }
}
