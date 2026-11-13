import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/ui_kit.dart';

/// Miqdor/foiz maydonlari uchun: raqam + bo'shliq (ajratgich sifatida).
final _kNumberOnly =
    FilteringTextInputFormatter.allow(RegExp(r"[0-9\s\u00A0']"));

/// Nomdan kelib chiqadigan barqaror rang — ro'yxat rang-barang ko'rinadi,
/// lekin bitta ingredient har doim bir xil rangda qoladi.
const kIngredientAvatarColors = [
  AppColors.primary,
  AppColors.accent,
  AppColors.success,
  AppColors.info,
  AppColors.warning,
];

Color ingredientAvatarColor(String name) {
  var h = 0;
  for (final c in name.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return kIngredientAvatarColors[h % kIngredientAvatarColors.length];
}

/// Bosh harfli rangli kvadrat — picker va kirim ro'yxatlarida bir xil
/// ko'rinish uchun bitta joyda.
class IngredientAvatar extends StatelessWidget {
  final String name;
  final double size;
  const IngredientAvatar({super.key, required this.name, this.size = 38});

  @override
  Widget build(BuildContext context) {
    final color = ingredientAvatarColor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
            fontSize: size * 0.42, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

/// Qidiruvli ingredient tanlash EKRANINI ochadi (navigator push).
/// Tanlangan ingredient Map ko'rinishida qaytadi (bekor qilinsa null).
///
/// Ilgari bottom sheet edi — kirim ekrani (fullscreenDialog) bilan birga
/// ikkalasi ketma-ket pastdan chiqib, ustma-ust dialogdek ko'rinardi.
/// Endi oddiy ekran sifatida ochiladi.
Future<Map<String, dynamic>?> showIngredientPicker(
  BuildContext context, {
  required List<dynamic> ingredients,
  bool allowCreate = true,
  bool showStock = false,
}) {
  return Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(
      builder: (_) => IngredientPickerScreen(
        ingredients: ingredients,
        allowCreate: allowCreate,
        showStock: showStock,
      ),
    ),
  );
}

class IngredientPickerScreen extends StatefulWidget {
  final List<dynamic> ingredients;

  /// Pastda «Yangi ingredient qo'shish» tugmasi — ro'yxatda yo'q bo'lsa
  /// shu yerning o'zida yaratib, darhol tanlab qaytadi.
  final bool allowCreate;

  /// Har bir qatorda ombordagi qoldiqni ham ko'rsatish (bozor uchun).
  final bool showStock;

  const IngredientPickerScreen({
    super.key,
    required this.ingredients,
    this.allowCreate = true,
    this.showStock = false,
  });

  @override
  State<IngredientPickerScreen> createState() => _IngredientPickerScreenState();
}

class _IngredientPickerScreenState extends State<IngredientPickerScreen> {
  final TextEditingController _searchC = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchC.addListener(() {
      setState(() => _query = _searchC.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  // Ro'yxatdan chiqmasdan yangi ingredient yaratish (bir joyning o'zida)
  Future<void> _createNew() async {
    final nameC = TextEditingController(text: _searchC.text.trim());
    final wasteC = TextEditingController(text: '0');
    String unit = 'gr';

    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setD) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Yangi ingredient'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: 'Nomi'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: unit,
                decoration: const InputDecoration(
                    labelText: 'Birlik (kg -> gr, l -> ml)'),
                items: const [
                  DropdownMenuItem(value: 'gr', child: Text('gramm (gr)')),
                  DropdownMenuItem(value: 'ml', child: Text('millilitr (ml)')),
                  DropdownMenuItem(value: 'dona', child: Text('dona')),
                  DropdownMenuItem(value: 'm', child: Text('metr (m)')),
                ],
                onChanged: (v) => setD(() => unit = v ?? 'gr'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: wasteC,
                keyboardType: TextInputType.number,
                inputFormatters: [_kNumberOnly],
                decoration: const InputDecoration(
                  labelText: 'Yo\'qotish % (tozalash chiqindisi)',
                  hintText: '0',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Bekor'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameC.text.trim();
                if (name.isEmpty) return;
                try {
                  final res = await ApiService().createIngredient({
                    'name': name,
                    'unit': unit,
                    'min_qty': 0,
                    'waste_percent': parseIntField(wasteC.text) ?? 0,
                  });
                  if (dctx.mounted) Navigator.pop(dctx, res);
                } catch (e) {
                  if (dctx.mounted) {
                    String msg = 'Saqlab bo\'lmadi';
                    if (e is DioException && e.response?.data is Map) {
                      msg = ((e.response!.data as Map)['message'] ?? msg)
                          .toString();
                    }
                    ScaffoldMessenger.of(dctx).showSnackBar(SnackBar(
                        content: Text(msg),
                        backgroundColor: AppColors.danger));
                  }
                }
              },
              child: const Text('Yaratish'),
            ),
          ],
        ),
      ),
    );
    if (created != null && mounted) {
      // Yaratilgan ingredient bilan picker yopiladi — chaqirgan ekranga
      // darhol tushadi
      Navigator.pop(context, created);
    }
  }

  /// Qidiruvga mos kelgan bo'lak nom ichida ajralib ko'rinadi.
  Widget _nameText(BuildContext context, String name) {
    final base = TextStyle(
      fontSize: context.s(14.5),
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    );
    final idx = _query.isEmpty ? -1 : name.toLowerCase().indexOf(_query);
    if (idx < 0) {
      return Text(name,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: base);
    }
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: name.substring(0, idx)),
        TextSpan(
          text: name.substring(idx, idx + _query.length),
          style: const TextStyle(
              fontWeight: FontWeight.w800, color: AppColors.primary),
        ),
        TextSpan(text: name.substring(idx + _query.length)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base,
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _query.isEmpty
        ? widget.ingredients
        : widget.ingredients
            .where((i) => (i['name'] ?? '')
                .toString()
                .toLowerCase()
                .contains(_query))
            .toList();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Ingredient tanlash',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        // Soni sarlavha YONIDA emas, o'ng chetda: orqaga tugmasi + uzun
        // sarlavha bilan bir qatorda tor telefonda joyga sig'masdi.
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text('${list.length} ta',
                    style: TextStyle(
                        fontSize: context.s(11.5),
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
            ),
          ),
        ],
      ),
      // TARTIB: ro'yxat TEPADA, qidiruv maydoni ESA PASTDA — barmoq va
      // klaviatura yonida. Hammasi body ichida turadi, shuning uchun
      // klaviatura ochilganda qidiruv ham, «yangi qo'shish» ham uning
      // USTIDA qoladi (body o'zi qisqaradi).
      body: KMaxWidth(
        maxWidth: 720,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: list.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'Hech narsa topilmadi',
                        subtitle: _query.isEmpty
                            ? null
                            : widget.allowCreate
                                ? '"${_searchC.text.trim()}" bo\'yicha mos '
                                    'ingredient yo\'q — pastdan yangi qo\'shing'
                                : '"${_searchC.text.trim()}" bo\'yicha mos '
                                    'ingredient yo\'q',
                      )
                    : ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: AppColors.borderSoft,
                          indent: context.s(38) + 20,
                        ),
                        itemBuilder: (_, i) {
                          final ing = list[i];
                          final name = '${ing['name']}';
                          return InkWell(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                            onTap: () => Navigator.pop(
                                context,
                                ing is Map<String, dynamic>
                                    ? ing
                                    : Map<String, dynamic>.from(
                                        ing as Map)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 7),
                              child: Row(
                                children: [
                                  IngredientAvatar(
                                      name: name, size: context.s(38)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _nameText(context, name),
                                        if (widget.showStock)
                                          Text(
                                            'qoldiq: ${formatQty(ing['count'], (ing['unit'] ?? '').toString())}',
                                            style: TextStyle(
                                                fontSize: context.s(11),
                                                color:
                                                    AppColors.textMuted),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceAlt,
                                      borderRadius: BorderRadius.circular(
                                          AppRadius.pill),
                                    ),
                                    child: Text('${ing['unit']}',
                                        style: TextStyle(
                                            fontSize: context.s(11.5),
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textMuted)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const Divider(height: 1, color: AppColors.borderSoft),
              // Doim ko'rinadigan "yangi qo'shish" — qidiruvda topilmasa ham
              // shu yerdan, qidiruv maydonining ustida.
              if (widget.allowCreate)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Material(
                    color: AppColors.successTint,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: InkWell(
                      onTap: _createNew,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                              color:
                                  AppColors.success.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_circle_rounded,
                                color: AppColors.success,
                                size: context.s(20)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _query.isEmpty
                                    ? 'Yangi ingredient qo\'shish'
                                    : '"${_searchC.text.trim()}" ni yangi qo\'shish',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: context.s(14),
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.success),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: TextField(
                  controller: _searchC,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Ingredient izlash...',
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppColors.textMuted),
                    // Klaviaturani yopish/qidiruvni tozalash — bitta tugma.
                    suffixIcon: IconButton(
                      icon: Icon(
                        _query.isEmpty
                            ? Icons.keyboard_hide_rounded
                            : Icons.close_rounded,
                        color: AppColors.textMuted,
                        size: 20,
                      ),
                      onPressed: () {
                        if (_query.isEmpty) {
                          FocusScope.of(context).unfocus();
                        } else {
                          _searchC.clear();
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
