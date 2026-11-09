import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/product_form_draft.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_filial_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/provider/upload_image_provider.dart';
import 'package:uz_ai_dev/admin/services/api_product_service.dart';
import 'package:uz_ai_dev/admin/ui/tech_card_editor_page.dart';
import 'package:uz_ai_dev/admin/ui/widgets/product_kind_radio.dart';
import 'package:uz_ai_dev/admin/ui/widgets/product_type_radio.dart';
import 'package:uz_ai_dev/core/catalog/product.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/data/sklad_registry.dart';
import 'package:uz_ai_dev/core/utils/product_sources.dart';
import 'package:uz_ai_dev/core/utils/money_input.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';

/// Qo'shish va tahrirlash uchun yagona mahsulot kartasi.
class ProductFormPage extends StatefulWidget {
  const ProductFormPage({
    super.key,
    this.product,
    this.initialCategoryId,
    this.initialSemiFinished = false,
  });

  final Product? product;
  final int? initialCategoryId;
  final bool initialSemiFinished;

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  late final ProductFormDraft _draft;
  late final TextEditingController _sostav;
  // Sotuv narxi (POS shu narxda sotadi). Faqat foydalanuvchi o'zgartirsa
  // yuboriladi: katalog retseptsiz yuklangan bo'lsa joriy narx noma'lum —
  // bo'sh maydon narxni 0 ga tushirib yubormasin.
  late final TextEditingController _salePrice;
  bool _salePriceDirty = false;
  // Qayerda tayyorlanadi (faqat Taom): 'center' | 'filial'.
  late String _madeAt = widget.product?.madeAt == 'center' ? 'center' : 'filial';
  bool _madeAtDirty = false;
  int? get _knownSalePrice => widget.product?.techCard?.salePrice;
  final _scroll = ScrollController();
  ProductTemplate? _template;
  File? _image;
  bool _saving = false;
  bool _submitted = false;
  String? _error;

  bool get _isNew => widget.product == null;
  Map<String, String> get _errors => _submitted ? _draft.validate() : {};

  @override
  void initState() {
    super.initState();
    _draft = ProductFormDraft(widget.product ??
        Product(
          id: 0,
          name: '',
          categoryId: widget.initialCategoryId ?? 0,
        ));
    if (_isNew) {
      _template = widget.initialSemiFinished
          ? ProductTemplate.preparation
          : ProductTemplate.ingredient;
      _draft.applyTemplate(_template!);
      if (widget.initialSemiFinished) _draft.unit = 'шт';
    }
    _draft.unit = normalizeProductType(_draft.unit);
    _sostav = TextEditingController(text: _draft.sostav);
    final sp = _knownSalePrice;
    _salePrice = TextEditingController(
        text: sp != null && sp > 0 ? formatMoneyInput(sp) : '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CategoryProviderAdmin>().getCategories();
      context.read<FilialProviderAdmin>().getFilials();
    });
  }

  @override
  void dispose() {
    _sostav.dispose();
    _salePrice.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _change(VoidCallback change) => setState(() {
        change();
        _error = null;
      });

  Widget _section(String title, String hint, List<Widget> children,
      {bool expandable = false}) {
    final detailsError =
        _errors.containsKey('waste') || _errors.containsKey('pieceWeight');
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: expandable
          ? ExpansionTile(
              key: ValueKey(detailsError),
              initiallyExpanded: detailsError,
              maintainState: true,
              title: Text(title),
              subtitle: Text(hint),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children)
              ],
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(hint, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 16),
                    ...children,
                  ]),
            ),
    );
  }

  Widget _field(String key, String label, String value,
          ValueChanged<String> onChanged,
          {String? hint, bool number = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          key: ValueKey(key),
          initialValue: value,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(
            labelText: label,
            helperText: hint,
            helperMaxLines: 3,
            errorText: _errors[key],
            errorMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
          onChanged: (text) => _change(() => onChanged(text)),
        ),
      );

  Widget _errorText(String key) => _errors[key] == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(_errors[key]!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        );

  void _toggle(List<int> ids, int id, bool selected) {
    _change(() {
      selected ? ids.add(id) : ids.remove(id);
    });
  }

  Widget _basics() {
    final categories = context.watch<CategoryProviderAdmin>();
    final categoryNames = {for (final c in categories.categories) c.id: c.name};
    // Yuklanish xatosi yoki eski kategoriya mavjud qiymatni yo'qotmasin.
    if (_draft.categoryId > 0) {
      categoryNames.putIfAbsent(
          _draft.categoryId,
          () => widget.product?.categoryName.isNotEmpty == true
              ? widget.product!.categoryName
              : 'Kategoriya #${_draft.categoryId}');
    }
    final units = {
      ...kProductTypeOptions,
      if (_draft.unit.isNotEmpty) _draft.unit
    };
    return _section('1. Asosiy ma’lumot',
        'Mahsulot nomi, kategoriyasi va hisob yuritiladigan birlik.', [
      if (_isNew) ...[
        DropdownButtonFormField<ProductTemplate>(
          key: const ValueKey('template'),
          initialValue: _template,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Mahsulot bilan nima qilamiz?',
              border: OutlineInputBorder()),
          items: [
            for (final t in ProductTemplate.values)
              DropdownMenuItem(value: t, child: Text(t.label))
          ],
          onChanged: (value) {
            if (value != null) {
              _change(() {
                _template = value;
                _draft.applyTemplate(value);
              });
            }
          },
        ),
        const SizedBox(height: 8),
        Text(_template!.hint),
        const SizedBox(height: 16),
      ] else ...[
        ProductKindRadioGroup(
            value: _draft.kind,
            onChanged: (kind) => _change(() => _draft.changeKind(kind))),
        const SizedBox(height: 16),
      ],
      _field('name', 'Mahsulot nomi', _draft.name, (v) => _draft.name = v),
      DropdownButtonFormField<int>(
        key: ValueKey('category-${_draft.categoryId}'),
        initialValue: _draft.categoryId > 0 ? _draft.categoryId : null,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: 'Kategoriya',
            errorText: _errors['category'],
            border: const OutlineInputBorder()),
        items: [
          for (final entry in categoryNames.entries)
            DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis))
        ],
        onChanged: (value) {
          if (value != null) _change(() => _draft.categoryId = value);
        },
      ),
      if (categories.isLoading) const LinearProgressIndicator(),
      if (categories.error != null)
        TextButton.icon(
          onPressed: categories.getCategories,
          icon: const Icon(Icons.refresh),
          label: const Text('Kategoriyalar yuklanmadi. Qayta urinish'),
        ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _draft.unit.isEmpty ? null : _draft.unit,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: 'O‘lchov birligi',
            errorText: _errors['unit'],
            border: const OutlineInputBorder()),
        items: [
          for (final unit in units)
            DropdownMenuItem(value: unit, child: Text(productUnitLabel(unit)))
        ],
        onChanged: (value) {
          if (value != null) _change(() => _draft.unit = value);
        },
      ),
    ]);
  }

  Widget _sales() {
    final provider = context.watch<FilialProviderAdmin>();
    final names = {for (final f in provider.filials) f.id: f.name};
    for (final id in _draft.filials) {
      names.putIfAbsent(id, () => 'Filial #$id');
    }
    return _section(
        '2. Sotuv', 'Qaysi filiallar bu mahsulotni buyurtma qila oladi?', [
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Sotuvda ko‘rinsin'),
        value: _draft.hasSales,
        onChanged: (value) => _change(() => _draft.sellable = value),
      ),
      if (_draft.kind == ProductKind.product) ...[
        const Text('Qayerda tayyorlanadi?',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'center',
                label: Text('Markazda (sex)'),
                icon: Icon(Icons.factory_outlined)),
            ButtonSegment(
                value: 'filial',
                label: Text('Filialda'),
                icon: Icon(Icons.storefront_outlined)),
          ],
          selected: {_madeAt},
          onSelectionChanged: (s) => setState(() {
            _madeAt = s.first;
            _madeAtDirty = true;
          }),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 12),
          child: Text(
            _madeAt == 'center'
                ? 'Sexda tayyorlanib filialga tayyor holda keladi. Kassada mahsulotning o‘zi yechiladi; filialda qoldiq yo‘q bo‘lsa sotilmaydi.'
                : 'Filialda tayyorlanadi. Kassada sotilganda retsept masalliqlari bo‘lim omboridan yechiladi.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
      ],
      if (_draft.hasSales && _draft.kind != ProductKind.pf) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _salePrice,
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsSeparatorInputFormatter()],
            decoration: InputDecoration(
              labelText: 'Sotuv narxi (so‘m)',
              helperText: _knownSalePrice == null && !_isNew
                  ? 'Bo‘sh qoldirilsa narx o‘zgarmaydi. Kassa (POS) shu narxda sotadi.'
                  : 'Kassa (POS) shu narxda sotadi. Retseptga tegmaydi.',
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => _salePriceDirty = true,
          ),
        ),
      ],
      if (_draft.hasSales) ...[
        _field('sellStep', 'Buyurtma qadami (${productUnitLabel(_draft.unit)})',
            _draft.sellStep, (v) => _draft.sellStep = v,
            number: true,
            hint: '«+» bosilganda qo‘shiladi. Bo‘sh qoldirilsa: 1 birlik.'),
        if (provider.isLoading) const LinearProgressIndicator(),
        if (provider.error != null)
          TextButton.icon(
            onPressed: provider.getFilials,
            icon: const Icon(Icons.refresh),
            label: const Text('Filiallar yuklanmadi. Qayta urinish'),
          ),
        if (!provider.isLoading && names.isEmpty)
          const Text('Filiallar ro‘yxati bo‘sh.'),
        _errorText('filials'),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final entry in names.entries)
            FilterChip(
              label: Text(entry.value),
              selected: _draft.filials.contains(entry.key),
              onSelected: (v) => _toggle(_draft.filials, entry.key, v),
            ),
        ]),
      ],
    ]);
  }

  Widget _purchases() {
    final names = Map<int, String>.of(SkladRegistry.names);
    for (final id in _draft.sklads) {
      names.putIfAbsent(id, () => 'Ombor #$id');
    }
    final fallbackStep =
        ProductFormDraft.parseStep(_draft.sellStep, _draft.unit);
    final buyDefault = fallbackStep != null && fallbackStep > 0
        ? formatQty(fallbackStep, _draft.unit)
        : '1';
    return _section(
        '3. Xarid', 'Qayerdan keladi va qaysi ombor buyurtma beradi?', [
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Sotib olinadi'),
        value: _draft.hasPurchases,
        onChanged: (value) => _change(() => _draft.purchasable = value),
      ),
      if (_draft.hasPurchases) ...[
        _field('buyStep', 'Xarid qadami (${productUnitLabel(_draft.unit)})',
            _draft.buyStep, (v) => _draft.buyStep = v,
            number: true,
            hint:
                'Masalan: un uchun 25 kg. Bo‘sh qoldirilsa: $buyDefault birlik. '
                'Bu «+» qadami; alohida qadoq konvertatsiyasi emas.'),
        const Text('Yuk qayerdan keladi'),
        _errorText('sources'),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final code in kProductSources)
            FilterChip(
              label: Text(productSourceLabel(code)),
              selected: _draft.sources.contains(code),
              onSelected: (v) => _change(() {
                v ? _draft.sources.add(code) : _draft.sources.remove(code);
              }),
            ),
        ]),
        const SizedBox(height: 12),
        const Text('Buyurtma beradigan omborlar'),
        _errorText('sklads'),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final entry in names.entries)
            FilterChip(
              label: Text(entry.value),
              selected: _draft.sklads.contains(entry.key),
              onSelected: (v) => _toggle(_draft.sklads, entry.key, v),
            ),
        ]),
      ],
    ]);
  }

  Widget _recipe() => _section('Retsept',
          'Masalliqlar, ishlab chiqarish miqdori va tayyorlash bosqichlari.', [
        Text(_draft.original.hasRecipe
            ? 'Retsept mavjud'
            : 'Retsept hali kiritilmagan'),
        if (_draft.kind == ProductKind.pf)
          const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                  'Yarim tayyor mahsulot boshqa retseptlarda ishlatiladi. '
                  'Hozirgi tartibda sotuv va xarid kataloglariga chiqmaydi.')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _saving ? null : () => _save(openRecipe: true),
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('Saqlab, retseptni ochish'),
        ),
      ]);

  Widget _details() => _section(
      'Qo‘shimcha ma’lumot',
      'Bu maydonlar ixtiyoriy. Kerak bo‘lgandagina to‘ldiring.',
      [
        _field('company', 'Ishlab chiqaruvchi / brend', _draft.companyName,
            (v) => _draft.companyName = v),
        TextFormField(
          controller: _sostav,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
              labelText: 'Mijozga ko‘rinadigan tarkib',
              helperText:
                  'Oddiy matn. Masalliq miqdorlari retseptda yuritiladi.',
              helperMaxLines: 2,
              border: OutlineInputBorder()),
          onChanged: (v) => _change(() => _draft.sostav = v),
        ),
        if (_draft.original.hasRecipe)
          TextButton.icon(
            onPressed: _fillSostav,
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Retseptdan to‘ldirish'),
          ),
        const SizedBox(height: 16),
        if (_draft.usesWaste) ...[
          Text('Tozalashdagi yo‘qotish (${_draft.wasteUnit})'),
          const SizedBox(height: 12),
          _field('wasteBase', 'Boshlang‘ich miqdor (${_draft.wasteUnit})',
              _draft.wasteBase, (v) => _draft.wasteBase = v,
              number: true),
          _field('wasteAmount', 'Yo‘qoladigan miqdor (${_draft.wasteUnit})',
              _draft.wasteAmount, (v) => _draft.wasteAmount = v,
              number: true),
          _errorText('waste'),
        ],
        if (_draft.usesPieceWeight)
          _field('pieceWeight', '1 dona og‘irligi (g)', _draft.pieceWeight,
              (v) => _draft.pieceWeight = v,
              number: true,
              hint: 'Masalan: tuxumni retseptga grammda kiritish uchun.'),
        if (_image != null)
          Image(
              image: appFileImageProvider(context, _image!.path,
                  displayWidth: 160),
              width: 160,
              height: 120,
              fit: BoxFit.cover)
        else if (_draft.imageUrl.isNotEmpty)
          AppNetworkImage(
              imageUrl: _draft.imageUrl.startsWith('http')
                  ? _draft.imageUrl
                  : '${AppUrls.baseUrl}${_draft.imageUrl}',
              width: 160,
              height: 120),
        Wrap(spacing: 8, children: [
          TextButton.icon(
              onPressed: () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Rasm tanlash')),
          TextButton.icon(
              onPressed: () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Suratga olish')),
          if (_image != null || _draft.imageUrl.isNotEmpty)
            TextButton(
                onPressed: () => _change(() {
                      _image = null;
                      _draft.imageUrl = '';
                    }),
                child: const Text('Rasmni olib tashlash')),
        ]),
      ],
      expandable: true);

  void _fillSostav() {
    final products = context.read<ProductProviderAdmin>().products;
    final byId = {for (final p in products) p.id: p};
    final names = _draft.original.techCard!.ingredientNames(pfCard: (id) {
      final product = byId[id];
      return product?.isPf == true ? product!.techCard : null;
    });
    _change(() {
      _draft.sostav = names.join(', ');
      _sostav.text = _draft.sostav;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
          source: source, maxWidth: 1920, maxHeight: 1080, imageQuality: 85);
      if (file != null && mounted) _change(() => _image = File(file.path));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Rasm ochilmadi. Qayta urinib ko‘ring.');
      }
    }
  }

  Future<void> _save({bool openRecipe = false}) async {
    if (_saving) return;
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (_draft.validate().isNotEmpty) {
      await _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      return;
    }
    setState(() => _saving = true);
    try {
      final provider = context.read<ProductProviderAdmin>();
      if (_image != null) {
        final url = await context
            .read<CategoryProviderAdminUpload>()
            .uploadImage(_image!);
        if (!mounted) return;
        if (url == null) {
          throw StateError('Rasm yuklanmadi. Qayta urinib ko‘ring.');
        }
        _draft.imageUrl = url;
        _image = null;
      }
      final saved = await provider.saveProduct(_draft.build());
      if (!mounted) return;
      if (saved == null) {
        setState(() => _error =
            provider.error?.replaceFirst('Exception: ', '') ??
                'Mahsulot saqlanmadi');
        await _scroll.animateTo(0,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        return;
      }
      // Sotuv narxi — alohida endpoint (retsept o'zgarmaydi). Faqat
      // foydalanuvchi maydonga tekkan bo'lsa va matn bo'sh bo'lmasa.
      if (_salePriceDirty &&
          _salePrice.text.trim().isNotEmpty &&
          saved.id > 0 &&
          _draft.kind != ProductKind.pf) {
        await ApiProductService()
            .setSalePrice(saved.id, parseMoney(_salePrice.text));
        if (!mounted) return;
        _salePriceDirty = false;
      }
      if (_madeAtDirty && saved.id > 0 && _draft.kind == ProductKind.product) {
        await ApiProductService().setMadeAt(saved.id, _madeAt);
        if (!mounted) return;
        _madeAtDirty = false;
      }
      // PopScope saqlash vaqtida qaytishni to'sadi; muvaffaqiyatda ochamiz.
      setState(() => _saving = false);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      // Navigatsiyadan OLDIN olinadi: sahifa yopilgach context ishonchsiz.
      final messenger = ScaffoldMessenger.of(context);
      if (openRecipe) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute<bool>(
              builder: (_) => TechCardEditorPage(product: saved),
            ),
            result: true);
      } else {
        Navigator.pop(context, true);
      }
      messenger
          .showSnackBar(const SnackBar(content: Text('Mahsulot saqlandi')));
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
        await _scroll.animateTo(0,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final errors = _errors;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar:
            AppBar(title: Text(_isNew ? 'Yangi mahsulot' : 'Mahsulot kartasi')),
        body: AbsorbPointer(
          absorbing: _saving,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            child: Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (errors.isNotEmpty || _error != null)
                      Card(
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(_error ?? errors.values.join('\n')))),
                    _basics(),
                    if (_draft.kind != ProductKind.pf) ...[
                      _sales(),
                      _purchases()
                    ],
                    if (_draft.kind != ProductKind.raw ||
                        _draft.original.techCard != null)
                      _recipe(),
                    _details(),
                  ]),
            )),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              key: const ValueKey('save-product'),
              onPressed: _saving ? null : () => _save(),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(_saving ? 'Saqlanmoqda…' : 'Saqlash'),
            ),
          ),
        ),
      ),
    );
  }
}
