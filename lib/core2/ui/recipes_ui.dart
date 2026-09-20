// core2/ui/recipes_ui.dart — mone_core retseptlari (shef, perm recipe.edit):
// RecipesUi — retseptlar ro'yxati (tovar nomi, versiyalar soni, oxirgi
// valid_from), qidiruv, «+» yangi retsept (tovar tanlash → birinchi
// versiya). RecipeDetailUi — versiyalar ro'yxati (valid_from) → versiya
// tafsiloti (qatorlar brutto/netto, base birlikdan kg/l ko'rinishda),
// «Yangi versiya» — RecipeVersionFormUi: sana + izoh + qatorlar (oldingi
// versiyadan nusxa), brutto/netto kg'da kiritiladi, BUTUN base yuboriladi.
// POST /recipes body: {good_id, name, version:{…}}; yield_qty base
// birlikda, yield_unit — ko'rsatish birligi (kg/l/pcs/portion).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_qty.dart';
import 'package:uz_ai_dev/core2/models/core_recipe.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/services/core_recipe_service.dart';
import 'package:uz_ai_dev/core2/ui/reports/recipe_cost_ui.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';
import 'package:uz_ai_dev/core2/ui/widgets/good_picker.dart';

class RecipesUi extends StatefulWidget {
  const RecipesUi({super.key});

  @override
  State<RecipesUi> createState() => _RecipesUiState();
}

class _RecipesUiState extends State<RecipesUi> {
  final _service = CoreRecipeService();
  List<CoreRecipe>? _list;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
    });
    try {
      final l = await _service.list();
      if (mounted) setState(() => _list = l);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _create() async {
    final good = await pickCoreGood(context);
    if (good == null || !mounted) return;
    final version = await Navigator.push<CoreRecipeVersion>(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeVersionFormUi(
          title: 'Yangi retsept: ${good.name}',
          base: null,
          // Chiqish birligi — tovar base'ining katta birligi (kg/l/pcs/m).
          yieldUnit: good.preferredUnit.unit,
        ),
      ),
    );
    if (version == null || !mounted) return;
    try {
      await _service.create(goodId: good.id, name: good.name, version: version);
      _load();
    } catch (e) {
      if (mounted) showCoreError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.select<CoreSession, bool>((s) => s.has(CorePerms.recipeEdit));
    final dict = context.read<CoreDictProvider>();
    final q = _q.toLowerCase();
    final list = (_list ?? const <CoreRecipe>[]).where((r) {
      if (q.isEmpty) return true;
      final name = r.title.isNotEmpty ? r.title : dict.goodName(r.goodId);
      return name.toLowerCase().contains(q) ||
          r.goodName.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('Retseptlar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: CoreConnectGate(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: coreInput('Qidirish', suffix: const Icon(Icons.search, size: 18)),
              ),
            ),
            Expanded(
              child: _error != null
                  ? CoreErrorView(message: _error!, onRetry: _load)
                  : _list == null
                      ? const Center(child: CircularProgressIndicator.adaptive())
                      : list.isEmpty
                          ? const Center(child: Text('Retsept yo\'q'))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                              itemCount: list.length,
                              itemBuilder: (_, i) {
                                final r = list[i];
                                final latest = r.latest;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.menu_book_outlined, color: kCoreAccentDark),
                                    title: Text(r.title.isNotEmpty ? r.title : dict.goodName(r.goodId),
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text(
                                      '${r.goodName.isNotEmpty && r.goodName != r.title ? '${r.goodName} · ' : ''}'
                                      '${r.versions.length} versiya'
                                      '${latest != null ? ' · oxirgi: ${coreDate(latest.validFrom)}' : ''}',
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => RecipeDetailUi(recipeId: r.id, initial: r)),
                                      );
                                      _load();
                                    },
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton(
              backgroundColor: kCoreAccent,
              foregroundColor: Colors.white,
              onPressed: _create,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class RecipeDetailUi extends StatefulWidget {
  final int recipeId;
  final CoreRecipe? initial;
  const RecipeDetailUi({super.key, required this.recipeId, this.initial});

  @override
  State<RecipeDetailUi> createState() => _RecipeDetailUiState();
}

class _RecipeDetailUiState extends State<RecipeDetailUi> {
  final _service = CoreRecipeService();
  CoreRecipe? _recipe;
  String? _error;
  int? _selectedVersionId;

  @override
  void initState() {
    super.initState();
    _recipe = widget.initial;
    _selectedVersionId = widget.initial?.latest?.id;
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _service.get(widget.recipeId);
      if (!mounted) return;
      setState(() {
        _recipe = r;
        _error = null;
        _selectedVersionId ??= r.latest?.id;
        if (!r.versions.any((v) => v.id == _selectedVersionId)) {
          _selectedVersionId = r.latest?.id;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _newVersion() async {
    final r = _recipe;
    if (r == null) return;
    final base = r.versions
        .where((v) => v.id == _selectedVersionId)
        .cast<CoreRecipeVersion?>()
        .firstWhere((_) => true, orElse: () => r.latest);
    final good = context.read<CoreDictProvider>().goodById(r.goodId);
    final v = await Navigator.push<CoreRecipeVersion>(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeVersionFormUi(
          title: 'Yangi versiya: ${r.name}',
          base: base,
          yieldUnit: base?.yieldUnit ?? good?.preferredUnit.unit ?? 'pcs',
        ),
      ),
    );
    if (v == null || !mounted) return;
    try {
      await _service.addVersion(r.id, v);
      _selectedVersionId = null;
      _load();
    } catch (e) {
      if (mounted) showCoreError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.select<CoreSession, bool>((s) => s.has(CorePerms.recipeEdit));
    final dict = context.read<CoreDictProvider>();
    final r = _recipe;
    final versions = [...?r?.versions]..sort((a, b) => b.validFrom.compareTo(a.validFrom));
    final sel = versions
        .where((v) => v.id == _selectedVersionId)
        .cast<CoreRecipeVersion?>()
        .firstWhere((_) => true, orElse: () => versions.isEmpty ? null : versions.first);

    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: Text(r?.title.isNotEmpty == true ? r!.title : 'Retsept',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          // Tannarx (kalkulyatsiya kartasi) — shu retsept mahsuloti bo'yicha.
          if (r != null)
            IconButton(
              tooltip: 'Kalkulyatsiya kartasi',
              onPressed: () => context.push(
                  RecipeCostUi(goodId: r.goodId, goodName: r.name)),
              icon: const Icon(Icons.calculate_outlined),
            ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: CoreConnectGate(
        child: r == null
            ? (_error != null
                ? CoreErrorView(message: _error!, onRetry: _load)
                : const Center(child: CircularProgressIndicator.adaptive()))
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                children: [
                  const Text('Versiyalar', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final v in versions) ...[
                          ChoiceChip(
                            label: Text(coreDate(v.validFrom), style: const TextStyle(fontSize: 12)),
                            selected: v.id == sel?.id,
                            selectedColor: kCoreAccent.withValues(alpha: 0.25),
                            onSelected: (_) => setState(() => _selectedVersionId = v.id),
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (sel != null) _versionCard(sel, dict),
                ],
              ),
      ),
      floatingActionButton: canEdit && r != null
          ? FloatingActionButton.extended(
              backgroundColor: kCoreAccent,
              foregroundColor: Colors.white,
              onPressed: _newVersion,
              icon: const Icon(Icons.add),
              label: const Text('Yangi versiya'),
            )
          : null,
    );
  }

  // Qator base birligi: server bergan `base_unit`, bo'lmasa lug'atdan.
  String _lineUnit(CoreRecipeLine l, CoreDictProvider dict) => l.baseUnit.isNotEmpty
      ? l.baseUnit
      : (dict.goodById(l.goodId)?.baseUnit ?? 'pcs');

  Widget _versionCard(CoreRecipeVersion v, CoreDictProvider dict) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          kv('Amal qiladi', coreDate(v.validFrom)),
          // yield_qty — base birlikda, yield_unit — ko'rsatish birligi (kg…).
          kv('Chiqish', coreFormatQtyAs(v.yieldQty, v.yieldUnit)),
          if (v.note.isNotEmpty) kv('Izoh', v.note),
          const Divider(),
          Row(
            children: [
              const Expanded(
                  child: Text('Ingredient', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5))),
              SizedBox(
                  width: 80,
                  child: Text('Brutto',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
              SizedBox(
                  width: 80,
                  child: Text('Netto',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
            ],
          ),
          for (final l in v.lines) ...[
            const Divider(height: 8),
            Row(
              children: [
                Expanded(
                    child: Text(l.goodName.isNotEmpty ? l.goodName : dict.goodName(l.goodId),
                        style: const TextStyle(fontSize: 13))),
                SizedBox(
                    width: 80,
                    child: Text(
                        coreFormatQtyUnit(l.qtyBrutto, _lineUnit(l, dict)),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12.5))),
                SizedBox(
                    width: 80,
                    child: Text(
                        coreFormatQtyUnit(l.qtyNetto, _lineUnit(l, dict)),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RecipeLineEdit {
  final CoreGood good;
  final TextEditingController brutto;
  final TextEditingController netto;
  _RecipeLineEdit(this.good, {int bruttoBase = 0, int nettoBase = 0})
      : brutto = TextEditingController(
            text: bruttoBase > 0 ? coreFormatQty(bruttoBase, good.baseUnit) : ''),
        netto = TextEditingController(
            text: nettoBase > 0 ? coreFormatQty(nettoBase, good.baseUnit) : '');
  void dispose() {
    brutto.dispose();
    netto.dispose();
  }
}

/// Yangi versiya formasi: sana + chiqish + qatorlar. Natija — CoreRecipeVersion
/// (pop orqali qaytadi; saqlashni chaqiruvchi bajaradi).
class RecipeVersionFormUi extends StatefulWidget {
  final String title;
  final CoreRecipeVersion? base;
  final String yieldUnit;
  const RecipeVersionFormUi({
    super.key,
    required this.title,
    required this.base,
    required this.yieldUnit,
  });

  @override
  State<RecipeVersionFormUi> createState() => _RecipeVersionFormUiState();
}

class _RecipeVersionFormUiState extends State<RecipeVersionFormUi> {
  String _date = todayIso();
  final _yield = TextEditingController();
  final _note = TextEditingController();
  final List<_RecipeLineEdit> _lines = [];
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final dict = context.read<CoreDictProvider>();
    final b = widget.base;
    if (b != null) {
      _yield.text = b.yieldQty > 0
          ? coreFormatInUnit(b.yieldQty, _unitOf(widget.yieldUnit))
          : '';
      for (final l in b.lines) {
        final g = dict.goodById(l.goodId) ??
            CoreGood(
                id: l.goodId,
                name: l.goodName,
                baseUnit: l.baseUnit.isNotEmpty ? l.baseUnit : 'mpcs');
        _lines.add(_RecipeLineEdit(g, bruttoBase: l.qtyBrutto, nettoBase: l.qtyNetto));
      }
    } else {
      _yield.text = '1';
    }
  }

  @override
  void dispose() {
    _yield.dispose();
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  /// Kiritish birligi: base kod (g/ml/mpcs/mm) → katta birlik; birlik kodi
  /// (kg/l/pcs/portion) bo'lsa — o'zi, `/units` faktori bilan.
  CoreGoodUnit _unitOf(String code) =>
      defaultDisplayUnit(code) ??
      CoreGoodUnit(unit: code, toBase: coreUnitFactor(code));

  void _submit() {
    final lines = <CoreRecipeLine>[];
    for (final l in _lines) {
      final u = _unitOf(l.good.baseUnit);
      final br = coreQtyFromUi(parseUiQty(l.brutto.text) ?? 0, u);
      var nt = coreQtyFromUi(parseUiQty(l.netto.text) ?? 0, u);
      if (nt == 0) nt = br; // netto kiritilmasa brutto bilan teng
      if (br <= 0 && nt <= 0) continue;
      lines.add(CoreRecipeLine(goodId: l.good.id, goodName: l.good.name, qtyBrutto: br, qtyNetto: nt));
    }
    if (lines.isEmpty) {
      showCoreInfo(context, 'Kamida bitta ingredient kiriting');
      return;
    }
    final yu = _unitOf(widget.yieldUnit);
    final yieldQty = coreQtyFromUi(parseUiQty(_yield.text) ?? 0, yu);
    Navigator.pop(
      context,
      CoreRecipeVersion(
        validFrom: _date,
        yieldQty: yieldQty <= 0 ? yu.toBase : yieldQty,
        // yield_unit — ko'rsatish birligi (kg/l/pcs…), base kod emas.
        yieldUnit: yu.unit,
        note: _note.text.trim(),
        lines: lines,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final yu = _unitOf(widget.yieldUnit);
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: Text(widget.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final d = await pickDate(context, _date);
                          if (d != null) setState(() => _date = d);
                        },
                        child: InputDecorator(
                          decoration: coreInput('Amal qiladi (valid_from)',
                              suffix: const Icon(Icons.calendar_today, size: 18)),
                          child: Text(coreDate(_date)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 130,
                      child: TextField(
                        controller: _yield,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        decoration: coreInput('Chiqish, ${yu.unit}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(controller: _note, decoration: coreInput('Izoh (ixtiyoriy)')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Expanded(
                        child: Text('Ingredientlar', style: TextStyle(fontWeight: FontWeight.bold))),
                    TextButton.icon(
                      onPressed: () async {
                        final g = await pickCoreGood(context);
                        if (g != null && mounted) setState(() => _lines.add(_RecipeLineEdit(g)));
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Tovar'),
                    ),
                  ],
                ),
                for (final l in _lines)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                                child: Text(l.good.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600))),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(() {
                                _lines.remove(l);
                                l.dispose();
                              }),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: l.brutto,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                                ],
                                decoration: coreInput('Brutto, ${_unitOf(l.good.baseUnit).unit}'),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: l.netto,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                                ],
                                decoration: coreInput('Netto, ${_unitOf(l.good.baseUnit).unit}'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: SafeArea(
              top: false,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                    backgroundColor: kCoreAccent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46)),
                child: const Text('Saqlash'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
