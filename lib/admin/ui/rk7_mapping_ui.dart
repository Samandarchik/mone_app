// admin/ui/rk7_mapping_ui.dart — RK7 «Mapping» tabi (Rk7MappingTab): tepada
// bog'lanmagan taomlar (GET /api/rk7/unmapped), pastda qidiruv bilan mapping
// ro'yxati (GET /api/rk7/mappings?q=) va bog'lash dialogi (POST /api/rk7/mappings).
// Dialogda mahsulot tanlangach «SH5 retsepti» bo'limi ham chiqadi
// (PLAN_RETSEPT §4) — _Sh5RecipeSection, fayl oxirida.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/product_model.dart';
import 'package:uz_ai_dev/admin/model/rk7_mapping_model.dart';
import 'package:uz_ai_dev/admin/model/rk7_shift_model.dart';
import 'package:uz_ai_dev/admin/model/sh5_recipe_model.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/services/rk7_service.dart';
import 'package:uz_ai_dev/admin/services/sh5_service.dart';
import 'package:uz_ai_dev/admin/ui/widgets/rk7_common.dart';
import 'package:uz_ai_dev/core/data/sklad_registry.dart';

// Mapping tabi — RK7 taomini Mone mahsulotiga bog'lash. Bog'lanmagan taomlar
// (sotuvda uchragan, lekin mapping'i yo'q) birinchi ko'rinadi, chunki ular
// skladdan yechilmay qolgan.
//
// MUHIM: per_portion — BUTUN son (1 porsiyaga necha SAQLASH birligi),
// serverga float YUBORILMAYDI. Mahsulot manbai — ProductProviderAdmin
// (CODEMAP: admin mahsulotlarining YAGONA manbai), sklad nomlari —
// SkladRegistry (CODEMAP: YAGONA manba, hardcode map yozilmaydi).
class Rk7MappingTab extends StatefulWidget {
  const Rk7MappingTab({super.key});

  @override
  State<Rk7MappingTab> createState() => _Rk7MappingTabState();
}

class _Rk7MappingTabState extends State<Rk7MappingTab>
    with AutomaticKeepAliveClientMixin {
  final Rk7Service _service = Rk7Service();
  final TextEditingController _searchController = TextEditingController();

  List<Rk7UnmappedDish> _unmapped = const [];
  List<Rk7Mapping> _mappings = const [];
  bool _loading = true;
  bool _mappingsLoading = false;
  String? _error;
  String _query = '';
  Timer? _debounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Mahsulotlar keshda bo'lsa qayta so'ralmaydi (ProductProviderAdmin).
      context.read<ProductProviderAdmin>().initializeProducts();
    });
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.fetchUnmapped(),
        _service.fetchMappings(q: _query),
      ]);
      if (!mounted) return;
      setState(() {
        _unmapped = results[0] as List<Rk7UnmappedDish>;
        _mappings = results[1] as List<Rk7Mapping>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  // Qidiruv o'zgarganda faqat mapping ro'yxati qayta so'raladi (debounce).
  void _onSearchChanged(String value) {
    _query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _loadMappings);
  }

  Future<void> _loadMappings() async {
    final query = _query;
    setState(() => _mappingsLoading = true);
    try {
      final list = await _service.fetchMappings(q: query);
      if (!mounted || query != _query) return;
      setState(() {
        _mappings = list;
        _mappingsLoading = false;
      });
    } catch (e) {
      if (!mounted || query != _query) return;
      setState(() => _mappingsLoading = false);
      rk7Snack(context, e.toString().replaceFirst('Exception: ', ''),
          error: true);
    }
  }

  // ─────────────────────────── Bog'lash dialogi ───────────────────────────

  Future<void> _openMappingDialog({
    required String dishGuid,
    required String dishName,
    Rk7Mapping? existing,
  }) async {
    final products = context.read<ProductProviderAdmin>().products;
    ProductModelAdmin? selected;
    final existingId = existing?.productId ?? 0;
    if (existingId > 0) {
      for (final p in products) {
        if (p.id == existingId) {
          selected = p;
          break;
        }
      }
    }

    String mode = existing?.deductMode ?? Rk7DeductMode.self;
    final perPortionController = TextEditingController(
      text: (existing?.perPortion ?? 1).toString(),
    );
    // §9.4: ixtiyoriy sklad override. 0 = sotuv nuqtasining skladi (default).
    // Registrda yo'q id (sklad o'chirilgan) bo'lsa ham tanlov yo'qolmasin.
    int skladId = existing?.skladId ?? 0;
    final skladIds = <int>[
      ...SkladRegistry.ids,
      if (skladId > 0 && !SkladRegistry.ids.contains(skladId)) skladId,
    ];

    // Retsept qo'llash / dialog ichida mapping saqlanishi — «Saqlash»siz
    // yopilsa ham ro'yxat yangilanishi uchun.
    bool dirty = false;

    // Apply serverda mapping.product_id ≠ 0 bo'lishini talab qiladi
    // (PLAN_RETSEPT §3), shuning uchun retseptni qo'llashdan oldin dialogdagi
    // joriy qiymatlar bilan mapping saqlanadi.
    Future<bool> ensureMapping() async {
      final product = selected;
      if (product == null) return false;
      final perPortion = int.tryParse(perPortionController.text.trim()) ?? 0;
      if (perPortion < 1) {
        if (mounted) {
          rk7Snack(context, 'per_portion 1 dan kichik bo\'lmasin', error: true);
        }
        return false;
      }
      try {
        await _service.saveMapping(
          dishGuid: dishGuid,
          productId: product.id,
          deductMode: mode,
          perPortion: perPortion,
          skladId: skladId,
        );
        dirty = true;
        return true;
      } catch (e) {
        if (mounted) {
          rk7Snack(context, e.toString().replaceFirst('Exception: ', ''),
              error: true);
        }
        return false;
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: Text(
              dishName.isEmpty ? dishGuid : dishName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mone mahsuloti (qidiruvli tanlash).
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await _pickProduct(dialogContext);
                      if (picked != null) {
                        setDialogState(() => selected = picked);
                      }
                    },
                    icon: const Icon(Icons.search, size: 18),
                    label: Text(
                      selected == null
                          ? 'Mone mahsulotini tanlash'
                          : selected!.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44),
                      alignment: Alignment.centerLeft,
                      foregroundColor: kRk7AccentDark,
                      side: BorderSide(color: Colors.grey.shade400),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // deduct_mode: self / ingredients.
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: mode == Rk7DeductMode.ingredients,
                    activeThumbColor: kRk7Accent,
                    onChanged: (v) => setDialogState(() => mode =
                        v ? Rk7DeductMode.ingredients : Rk7DeductMode.self),
                    title: const Text(
                      'Ingredientlar bo\'yicha yechish',
                      style: TextStyle(fontSize: 13.5),
                    ),
                    subtitle: Text(
                      mode == Rk7DeductMode.ingredients
                          ? 'ingredients — tex karta ingredientlari yechiladi'
                          : 'self — tayyor mahsulot o\'zi yechiladi',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // per_portion — BUTUN son (float yo'q).
                  TextField(
                    controller: perPortionController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'per_portion',
                      hintText: '1',
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: kRk7Accent, width: 2),
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '1 porsiyaga necha saqlash birligi (шт → 1, кг mahsulotga '
                    'gramm). Faqat butun son.',
                    style:
                        TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  // sklad_id — ixtiyoriy override (0 = nuqta skladi).
                  DropdownButtonFormField<int>(
                    initialValue: skladId,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                        value: 0,
                        child: Text('Nuqta skladi'),
                      ),
                      for (final id in skladIds)
                        DropdownMenuItem(
                          value: id,
                          child: Text(SkladRegistry.nameOf(id)),
                        ),
                    ],
                    onChanged: (v) => setDialogState(() => skladId = v ?? 0),
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    decoration: const InputDecoration(
                      labelText: 'Sklad (ixtiyoriy)',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: kRk7Accent, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Bo\'sh qoldirilsa (Nuqta skladi) sotuv nuqtasining '
                    'skladidan yechiladi.',
                    style:
                        TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                  ),
                  // SH5 retsepti — faqat mahsulot tanlangach so'raladi;
                  // retsept topilmasa bo'lim jim yo'qoladi (PLAN_RETSEPT §4).
                  if (selected != null)
                    _Sh5RecipeSection(
                      key: ValueKey('sh5-recipe-$dishGuid'),
                      dishGuid: dishGuid,
                      ensureMapping: ensureMapping,
                      onApplied: () {
                        dirty = true;
                        setDialogState(() => mode = Rk7DeductMode.ingredients);
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Bekor qilish'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kRk7Accent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Saqlash'),
              ),
            ],
          );
        },
      ),
    );

    final product = selected;
    final perPortion = int.tryParse(perPortionController.text.trim()) ?? 0;
    perPortionController.dispose();

    if (!mounted) return;
    if (saved != true) {
      // Retsept qo'llangan (yoki shu yo'lda mapping saqlangan) bo'lsa ro'yxat
      // eskirmasin.
      if (dirty) await _load();
      return;
    }
    if (product == null) {
      rk7Snack(context, 'Mahsulot tanlanmadi', error: true);
      return;
    }
    if (perPortion < 1) {
      rk7Snack(context, 'per_portion 1 dan kichik bo\'lmasin', error: true);
      return;
    }

    try {
      await _service.saveMapping(
        dishGuid: dishGuid,
        productId: product.id,
        deductMode: mode,
        perPortion: perPortion,
        skladId: skladId,
      );
      if (!mounted) return;
      rk7Snack(context, 'Bog\'lanish saqlandi');
      await _load();
    } catch (e) {
      if (!mounted) return;
      rk7Snack(context, e.toString().replaceFirst('Exception: ', ''),
          error: true);
    }
  }

  // Mone mahsulotini qidiruvli tanlash (manba: ProductProviderAdmin).
  Future<ProductModelAdmin?> _pickProduct(BuildContext dialogContext) {
    final all = dialogContext.read<ProductProviderAdmin>().products;
    String query = '';
    return showDialog<ProductModelAdmin>(
      context: dialogContext,
      builder: (pickerContext) => StatefulBuilder(
        builder: (pickerContext, setPickerState) {
          final q = query.trim().toLowerCase();
          final list = q.isEmpty
              ? all
              : all
                  .where((p) => p.name.toLowerCase().contains(q))
                  .toList(growable: false);
          return AlertDialog(
            contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (v) => setPickerState(() => query = v),
                    decoration: const InputDecoration(
                      hintText: 'Mahsulot qidirish...',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: kRk7Accent, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: list.isEmpty
                        ? const Center(child: Text('Hech narsa topilmadi'))
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (context, index) {
                              final product = list[index];
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  product.name,
                                  style: const TextStyle(fontSize: 13.5),
                                ),
                                subtitle: Text(
                                  product.type,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                onTap: () =>
                                    Navigator.pop(pickerContext, product),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(pickerContext),
                child: const Text('Yopish'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─────────────────────────────── Build ───────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _load,
      color: kRk7Accent,
      child: _body(),
    );
  }

  Widget _body() {
    if (_loading && _mappings.isEmpty && _unmapped.isEmpty) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_error != null && _mappings.isEmpty && _unmapped.isEmpty) {
      return rk7ErrorState(_error!, onRetry: _load);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // 1) Bog'lanmaganlar — birinchi ko'rinadi.
        _sectionTitle(
          'Bog\'lanmagan: ${_unmapped.length}',
          color: _unmapped.isEmpty ? Colors.black87 : Colors.red.shade700,
        ),
        if (_unmapped.isEmpty)
          _hint('Bog\'lanmagan taom yo\'q — hammasi mahsulotga bog\'langan')
        else
          for (final dish in _unmapped) _unmappedRow(dish),

        // 2) Qidiruv + mavjud mappinglar.
        const SizedBox(height: 12),
        _searchField(),
        _sectionTitle('Bog\'lanishlar (${_mappings.length})'),
        if (_mappingsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        else if (_mappings.isEmpty)
          _hint('Hech narsa topilmadi')
        else
          for (final mapping in _mappings) _mappingRow(mapping),
      ],
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'RK7 taom nomi yoki kodi...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                    setState(() {});
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kRk7Accent, width: 2),
          ),
        ),
      ),
    );
  }

  // Bog'lanmagan taom qatori: nom, oxirgi sana, jami qty (porsiya).
  Widget _unmappedRow(Rk7UnmappedDish dish) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openMappingDialog(
          dishGuid: dish.dishGuid,
          dishName: dish.dishName,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dish.dishName.isEmpty ? dish.dishGuid : dish.dishName,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dish.lastDate.isEmpty
                          ? '${formatPortions(dish.qtyMilli)} porsiya'
                          : 'oxirgi: ${rk7Date(dish.lastDate)} · '
                              '${formatPortions(dish.qtyMilli)} porsiya',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.link, size: 20, color: Colors.red.shade400),
            ],
          ),
        ),
      ),
    );
  }

  // Mapping qatori: RK7 nomi/kodi → mahsulot, rejim va per_portion.
  Widget _mappingRow(Rk7Mapping mapping) {
    final subtitle = mapping.isMapped
        ? '${mapping.productName.isEmpty ? 'Mahsulot #${mapping.productId}' : mapping.productName}'
            ' · ${mapping.deductMode} · ${mapping.perPortion}'
        : 'bog\'lanmagan';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openMappingDialog(
          dishGuid: mapping.dishGuid,
          dishName: mapping.dishName,
          existing: mapping,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mapping.dishCode.isEmpty
                          ? mapping.dishName
                          : '${mapping.dishCode} · ${mapping.dishName}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: mapping.isMapped
                            ? Colors.grey.shade600
                            : Colors.red.shade700,
                      ),
                    ),
                    // §9.4: sklad override — 0 bo'lsa hech narsa ko'rsatilmaydi.
                    if (mapping.hasSkladOverride) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: rk7Badge(
                          SkladRegistry.nameOf(mapping.skladId),
                          color: kRk7AccentDark,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.bold,
          color: color ?? Colors.black87,
        ),
      ),
    );
  }

  Widget _hint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
      ),
    );
  }
}

// ───────────────────────── SH5 retsepti bo'limi ─────────────────────────

// Bog'lash dialogidagi «SH5 retsepti» bloki (PLAN_RETSEPT §4): taomga mos
// SH5 kalkulyatsiyasi topilsa ingredientlarni (miqdor + mos Mone mahsuloti
// yoki QIZIL «topilmadi») ko'rsatadi va bitta tugma bilan tex karta qilib
// qo'llaydi. Retsept topilmasa (404/bo'sh) hech narsa chizmaydi.
class _Sh5RecipeSection extends StatefulWidget {
  const _Sh5RecipeSection({
    super.key,
    required this.dishGuid,
    required this.ensureMapping,
    required this.onApplied,
  });

  final String dishGuid;

  /// Apply'dan oldin mapping saqlanadi (server product_id ≠ 0 talab qiladi).
  /// false — saqlanmadi, qo'llash to'xtaydi.
  final Future<bool> Function() ensureMapping;

  /// Muvaffaqiyat: dialogdagi deduct_mode switch «ingredients» ga o'tadi.
  final VoidCallback onApplied;

  @override
  State<_Sh5RecipeSection> createState() => _Sh5RecipeSectionState();
}

class _Sh5RecipeSectionState extends State<_Sh5RecipeSection> {
  final Sh5Service _sh5 = Sh5Service();

  Sh5DishRecipe? _recipe;
  bool _loading = true;
  bool _applying = false;
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final recipe = await _sh5.fetchRecipeByDish(widget.dishGuid);
      if (!mounted) return;
      setState(() {
        _recipe = recipe;
        _loading = false;
      });
    } catch (_) {
      // Retsept qo'shimcha imkoniyat — xatosi bog'lash oqimini buzmasin.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _apply({bool overwrite = false}) async {
    setState(() => _applying = true);
    try {
      if (!await widget.ensureMapping()) return;
      await _sh5.applyRecipe(dishGuid: widget.dishGuid, overwrite: overwrite);
      if (!mounted) return;
      setState(() => _applied = true);
      widget.onApplied();
      rk7Snack(context, 'Tex karta SH5 retseptidan yaratildi');
    } on Sh5RecipeApplyException catch (e) {
      if (!mounted) return;
      if (e.techCardExists && !overwrite) {
        final replace = await _confirmOverwrite();
        if (replace == true) {
          await _apply(overwrite: true);
          return;
        }
      } else if (e.unmatched.isNotEmpty) {
        await _showUnmatched(e.unmatched);
      } else if (mounted) {
        rk7Snack(context, e.message, error: true);
      }
    } catch (e) {
      if (!mounted) return;
      rk7Snack(context, e.toString().replaceFirst('Exception: ', ''),
          error: true);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<bool?> _confirmOverwrite() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tex karta mavjud', style: TextStyle(fontSize: 15)),
        content: const Text(
          'Mahsulotda tex karta bor. Almashtiraylikmi?',
          style: TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Yo\'q'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kRk7Accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ha, almashtir'),
          ),
        ],
      ),
    );
  }

  // 409 unmatched — qisman tex karta yozilmaydi, admin avval shu masalliqlarni
  // Mone'da ochishi (yoki nomini moslashi) kerak.
  Future<void> _showUnmatched(List<String> names) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Mos kelmagan masalliqlar',
          style: TextStyle(fontSize: 15),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final name in names)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• $name',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Avval bu mahsulotlarni oching yoki nomini moslang.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Yopish'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 14),
        child: LinearProgressIndicator(minHeight: 2, color: kRk7Accent),
      );
    }
    final recipe = _recipe;
    if (recipe == null) return const SizedBox.shrink();

    final unmatchedCount = recipe.unmatchedNames.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.receipt_long, size: 18, color: kRk7AccentDark),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'SH5 retsepti',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
            ),
            if (unmatchedCount > 0)
              rk7Badge('topilmadi: $unmatchedCount', color: Colors.red.shade700),
          ],
        ),
        if (recipe.name.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            recipe.group.isEmpty
                ? recipe.name
                : '${recipe.name} · ${recipe.group}',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
        ],
        const SizedBox(height: 6),
        for (final item in recipe.ingredients) _ingredientRow(item),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _applying ? null : () => _apply(),
            icon: _applying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(_applied ? Icons.check : Icons.playlist_add, size: 18),
            label: Text(_applied ? 'Qo\'llandi' : 'Retseptni qo\'llash'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kRk7Accent,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  // Ingredient qatori: nom + miqdor (qty_micro'dan), ostida mos Mone mahsuloti
  // yoki QIZIL «topilmadi».
  Widget _ingredientRow(Sh5RecipeIngredient item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.matched ? Icons.check_circle_outline : Icons.error_outline,
            size: 16,
            color: item.matched ? Colors.green.shade600 : Colors.red.shade600,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 1),
                Text(
                  item.matched
                      ? (item.matchedProductName.isEmpty
                          ? 'Mahsulot #${item.matchedProductId}'
                          : item.matchedProductName)
                      : 'topilmadi',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight:
                        item.matched ? FontWeight.normal : FontWeight.w600,
                    color: item.matched
                        ? Colors.grey.shade600
                        : Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            item.qtyLabel,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
