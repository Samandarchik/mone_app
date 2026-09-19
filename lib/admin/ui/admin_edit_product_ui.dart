// admin/ui/admin_edit_product_ui.dart — mavjud mahsulotni tahrirlash formasi
// (EditProductPage): ProductProviderAdmin.updateProduct; CategoryProviderAdmin/
// FilialProviderAdmin, rasm CategoryProviderAdminUpload. Tex karta bu yerda emas —
// _techController mavjud kartani o'zgarmay saqlaydi va «Состав» avto-to'ldirishga ishlatiladi.
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/product_model.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_filial_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/provider/upload_image_provider.dart';
import 'package:uz_ai_dev/admin/ui/widgets/product_type_radio.dart';
import 'package:uz_ai_dev/admin/ui/widgets/tech_card_section.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/data/sklad_registry.dart';
import 'package:uz_ai_dev/core/utils/product_sources.dart';

class EditProductPage extends StatefulWidget {
  final ProductModelAdmin product;

  const EditProductPage({super.key, required this.product});

  @override
  State<EditProductPage> createState() => _EditProductPageState();
}

class _EditProductPageState extends State<EditProductPage> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  late TextEditingController _nameController;
  String? _selectedType;
  late TextEditingController companyController;
  late TextEditingController ingredientsController;
  late TextEditingController grammControlle;
  late TextEditingController bozorGrammController;
  // Tozalash yo'qotishi (faqat кг/л oilasida ko'rinadi), butun gramm.
  late TextEditingController wasteBaseController;
  late TextEditingController wasteAmountController;
  // «1 шт og'irligi» (gramm) — faqat xom шт mahsulotda ko'rinadi
  // (pf og'irligi o'z tex kartasidan olinadi).
  late TextEditingController pieceWeightController;
  late int _selectedCategoryId;
  late List<int> _selectedFilials;

  File? _selectedImage;
  bool _imageChanged = false;
  String? _currentImageUrl;

  // Ombor → yuk keltiruvchi oqimi uchun yangi maydonlar
  late bool _moneApp;
  late bool _bozor;
  // Yuk qayerdan keladi — bir nechta manba tanlanishi mumkin
  // (Samarqand + Toshkent).
  late Set<String> _selectedSources;
  late List<int> _selectedSklads;

  // Полуфабрикат — ishlab chiqariladi, sotilmaydi; tex kartalarda ingredient.
  late bool _isSemiFinished;

  // Tarkib (tex karta)
  late final TechCardController _techController;

  // «Состав» switch: yoniq bo'lsa Состав tarkib nomlaridan to'ladi (read-only),
  // eski erkin matn _savedComment ga saqlanadi.
  late bool _compositionAsIngredients;
  late String _savedComment;

  // Skladlar — SkladRegistry (superadmin serverda tahrirlaydi).
  Map<int, String> get _skladOptions => SkladRegistry.names;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product.name);
    final normalizedType = normalizeProductType(widget.product.type);
    _selectedType = normalizedType.isEmpty ? null : normalizedType;
    ingredientsController =
        TextEditingController(text: widget.product.ingredients);
    companyController = TextEditingController(text: widget.product.companyName);
    grammControlle = TextEditingController(
      text: (widget.product.grams ?? 1).toString(),
    );
    bozorGrammController = TextEditingController(
      text: widget.product.bozorGrams?.toString() ?? '',
    );
    wasteBaseController = TextEditingController(
      text: widget.product.wasteBase > 0
          ? widget.product.wasteBase.toString()
          : '',
    );
    wasteAmountController = TextEditingController(
      text: widget.product.wasteAmount > 0
          ? widget.product.wasteAmount.toString()
          : '',
    );
    pieceWeightController = TextEditingController(
      text: widget.product.pieceWeightG > 0
          ? widget.product.pieceWeightG.toString()
          : '',
    );

    _selectedCategoryId = widget.product.categoryId;
    _selectedFilials = List.from(widget.product.filials);
    _currentImageUrl = widget.product.imageUrl;

    _moneApp = widget.product.moneApp;
    _bozor = widget.product.bozor;
    // Faqat ma'lum manbalar (checkbox'da ko'rinadiganlar); hech biri
    // qolmasa — ilgarigidek standart Samarqand.
    _selectedSources = widget.product.sources
        .where(kProductSourceLabels.containsKey)
        .toSet();
    if (_selectedSources.isEmpty) {
      _selectedSources.add(kDefaultProductSource);
    }
    _selectedSklads = List.from(widget.product.sklads);
    _isSemiFinished = widget.product.isSemiFinished;

    _techController = TechCardController(widget.product.techCard);

    // «Состав» switch holatini saqlangan ma'lumotdan tiklaymiz.
    _compositionAsIngredients = widget.product.compositionAsIngredients;
    _savedComment = widget.product.comment ?? '';
    if (_compositionAsIngredients) {
      // Yoniq bo'lsa «Состав» nomlardan to'ladi (read-only).
      ingredientsController.text = _compositionNames();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CategoryProviderAdmin>().getCategories();
      context.read<FilialProviderAdmin>().getFilials();
    });
  }

  // ---- Tozalash yo'qotishi (waste) yordamchilari ----
  int get _wasteBaseVal => int.tryParse(wasteBaseController.text.trim()) ?? 0;
  int get _wasteAmountVal =>
      int.tryParse(wasteAmountController.text.trim()) ?? 0;
  // Noto'g'ri kombinatsiya: qizil eslatma ko'rinadi, saqlashda 0/0 yuboriladi.
  bool get _wasteInvalid =>
      _wasteBaseVal > 0 && _wasteAmountVal > 0 && _wasteAmountVal >= _wasteBaseVal;
  bool get _wasteValid =>
      _wasteBaseVal > 0 && _wasteAmountVal > 0 && _wasteAmountVal < _wasteBaseVal;
  // Faqat кг/л oilasida ma'noga ega.
  bool get _wasteApplies => qtyUnitFactor(_selectedType) == 1000;

  // ---- «1 шт og'irligi» (piece_weight_g) yordamchilari ----
  // Faqat xom шт mahsulotda (pf emas) — tex kartada grammda kiritish uchun.
  bool get _pieceWeightApplies => _selectedType == 'шт' && !_isSemiFinished;
  int get _pieceWeightVal =>
      int.tryParse(pieceWeightController.text.trim()) ?? 0;

  // «Состав» uchun: tex kartadagi showInSostav=true nomlarni vergul bilan
  // birlashtiradi; полуфабрикат qatori ichidagi masalliq nomlariga yoyiladi.
  String _compositionNames() {
    final byId = {
      for (final p in context.read<ProductProviderAdmin>().products) p.id: p
    };
    return _techController.sostavNames(pfCard: (id) {
      final p = byId[id];
      return (p != null && p.isSemiFinished) ? p.techCard : null;
    }).join(', ');
  }

  void _onCompositionSwitchChanged(bool value) {
    setState(() {
      if (value) {
        // YONIQ: joriy matnni comment ga saqlab, maydonni nomlardan to'ldiramiz.
        _savedComment = ingredientsController.text;
        _compositionAsIngredients = true;
        ingredientsController.text = _compositionNames();
      } else {
        // O'CHIQ: comment dagi eski matnni tiklaymiz.
        _compositionAsIngredients = false;
        ingredientsController.text = _savedComment;
      }
    });
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        if (!mounted) return;
        setState(() {
          _selectedImage = File(pickedFile.path);
          _imageChanged = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rasm tanlashda Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        if (!mounted) return;
        setState(() {
          _selectedImage = File(pickedFile.path);
          _imageChanged = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rasm olishda Ошибка: $e')),
        );
      }
    }
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Rasm tanlash'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Galereyadan'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Kameradan'),
                onTap: () {
                  Navigator.pop(context);
                  _takePhoto();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
      _currentImageUrl = null;
      _imageChanged = true;
    });
  }

  Widget _buildImageWidget() {
    // Yangi rasm tanlangan bo'lsa
    if (_selectedImage != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          _selectedImage!,
          width: double.infinity,
          height: 200,
          fit: BoxFit.cover,
        ),
      );
    }

    // Mavjud rasm bor bo'lsa
    if (_currentImageUrl != null && _currentImageUrl!.isNotEmpty) {
      // Base URL qo'shish
      final String fullImageUrl = _currentImageUrl!.startsWith('http')
          ? _currentImageUrl!
          : '${AppUrls.baseUrl}$_currentImageUrl';

      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: fullImageUrl,
          width: double.infinity,
          height: 200,
          fit: BoxFit.cover,
          errorWidget: (context, error, stackTrace) {
            return _buildPlaceholder();
          },
        ),
      );
    }

    // Rasm yo'q bo'lsa
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate, size: 50, color: Colors.grey[600]),
        const SizedBox(height: 8),
        Text(
          'Rasm tanlash',
          style: TextStyle(color: Colors.grey[600]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактирование продукта'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Image section
            GestureDetector(
              onTap: _showImageSourceDialog,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[200],
                ),
                child: Stack(
                  children: [
                    Center(child: _buildImageWidget()),
                    if (_selectedImage != null ||
                        (_currentImageUrl != null &&
                            _currentImageUrl!.isNotEmpty))
                      Positioned(
                        top: 8,
                        right: 8,
                        child: CircleAvatar(
                          backgroundColor: Colors.red,
                          child: IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 20),
                            onPressed: _removeImage,
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: CircleAvatar(
                        backgroundColor: Colors.blue,
                        child: IconButton(
                          icon: const Icon(Icons.edit,
                              color: Colors.white, size: 20),
                          onPressed: _showImageSourceDialog,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Upload progress indicator
            Consumer<CategoryProviderAdminUpload>(
              builder: (context, provider, child) {
                if (provider.isUploading) {
                  return Column(
                    children: [
                      LinearProgressIndicator(value: provider.uploadProgress),
                      const SizedBox(height: 8),
                      Text(
                        'Загрузка: ${(provider.uploadProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Название продукта',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Введите название продукта';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            ProductTypeRadioGroup(
              value: _selectedType,
              onChanged: (value) {
                setState(() {
                  _selectedType = value;
                });
              },
            ),
            // Tozalash yo'qotishi — faqat кг/л oilasidagi mahsulotlarda.
            if (_wasteApplies) ...[
              const SizedBox(height: 16),
              const Text(
                'Tozalashda yo\'qotish (ixtiyoriy)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: wasteBaseController,
                      decoration: const InputDecoration(
                        labelText: 'Necha grammdan (gr)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: wasteAmountController,
                      decoration: const InputDecoration(
                        labelText: 'Nechasi yo\'qoladi (gr)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              if (_wasteInvalid)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Yo\'qotish umumiy grammdan kichik bo\'lishi kerak — '
                    'aks holda saqlanmaydi (0)',
                    style: TextStyle(fontSize: 12, color: Colors.red[700]),
                  ),
                ),
            ],
            // «1 шт og'irligi» — faqat xom шт mahsulotda (pf og'irligi
            // tex kartadan). Tex kartada grammda kiritish uchun kerak.
            if (_pieceWeightApplies) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: pieceWeightController,
                decoration: const InputDecoration(
                  labelText: '1 шт og\'irligi (gr, ixtiyoriy)',
                  helperText:
                      'Tex kartada grammda kiritish uchun (masalan tuxum)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
            ],
            SizedBox(
              height: 20,
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Состав = из ингредиентов',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                Switch(
                  value: _compositionAsIngredients,
                  onChanged: _onCompositionSwitchChanged,
                ),
              ],
            ),
            TextFormField(
              controller: ingredientsController,
              readOnly: _compositionAsIngredients,
              decoration: const InputDecoration(
                labelText: 'Состав',
                border: OutlineInputBorder(),
                alignLabelWithHint: true, // label pastga joylashsin
              ),
              keyboardType: TextInputType.multiline, // ko‘p qatorli matn uchun
              maxLines: null, // cheklanmagan qatorlar
              textInputAction:
                  TextInputAction.newline, // Enter yangi qator ochadi
            ),
            SizedBox(
              height: 20,
            ),
            TextFormField(
              controller: companyController,
              decoration: const InputDecoration(
                labelText: 'Компания',
                border: OutlineInputBorder(),
                alignLabelWithHint: true, // label pastga joylashsin
              ),
              keyboardType: TextInputType.multiline, // ko‘p qatorli matn uchun
              maxLines: null, // cheklanmagan qatorlar
              textInputAction:
                  TextInputAction.newline, // Enter yangi qator ochadi
            ),
            SizedBox(
              height: 20,
            ),
            TextFormField(
              controller: grammControlle,
              decoration: const InputDecoration(
                labelText: 'Mone gramm',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return null; // bo‘sh bo‘lsa ruxsat
                }

                final number = double.tryParse(value);
                if (number == null) {
                  return "Принимаются только цифры.";
                }

                return null;
              },
            ),
            const SizedBox(height: 16),
            Consumer<CategoryProviderAdmin>(
              builder: (context, provider, child) {
                if (provider.isLoading) {
                  return const Center(
                      child: CircularProgressIndicator.adaptive());
                }
                return DropdownButtonFormField<int>(
                  initialValue: _selectedCategoryId,
                  decoration: const InputDecoration(
                    labelText: 'Категория',
                    border: OutlineInputBorder(),
                  ),
                  items: provider.categories.map((category) {
                    return DropdownMenuItem<int>(
                      value: category.id,
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * .7,
                        child: Text(
                          category.name,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCategoryId = value!;
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 16),
            // Полуфабрикат: yoqilganda birlik odatda «шт» (dona hisobida),
            // lekin boshqa birlik ham tanlash mumkin.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Полуфабрикат'),
              subtitle: const Text(
                'Ishlab chiqariladi, sotilmaydi — tex kartalarda '
                'ingredient bo\'ladi (dona hisobida)',
                style: TextStyle(fontSize: 12),
              ),
              value: _isSemiFinished,
              onChanged: (value) {
                setState(() {
                  _isSemiFinished = value;
                  // Odatiy birlik — «шт» (biskvit dona hisobida).
                  if (value && (_selectedType == null || _selectedType!.isEmpty)) {
                    _selectedType = 'шт';
                  }
                });
              },
            ),
            // Mone app / Bozor / Yuk manbai
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mone app'),
              value: _moneApp,
              onChanged: (value) {
                setState(() {
                  _moneApp = value;
                });
              },
            ),
            // Filiallar tanlovi faqat Mone app yoqilganda ko'rinadi
            if (_moneApp)
              Consumer<FilialProviderAdmin>(
                builder: (context, provider, child) {
                  if (provider.isLoading) {
                    return const Center(
                        child: CircularProgressIndicator.adaptive());
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      const Text(
                        'Филиалы:',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...provider.filials.map((filial) {
                        return CheckboxListTile(
                          title: Text(filial.name),
                          value: _selectedFilials.contains(filial.id),
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                _selectedFilials.add(filial.id);
                              } else {
                                _selectedFilials.remove(filial.id);
                              }
                            });
                          },
                        );
                      }),
                    ],
                  );
                },
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bozor'),
              value: _bozor,
              onChanged: (value) {
                setState(() {
                  _bozor = value;
                });
              },
            ),
            // Bozor yoqilganda: bozor grammi, yuk manbalari (checkbox — bir
            // nechtasi mumkin) va sklad tanlovi (checkbox)
            if (_bozor) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: bozorGrammController,
                decoration: const InputDecoration(
                  labelText: 'Bozor gramm',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return null; // bo‘sh bo‘lsa ruxsat
                  }
                  if (double.tryParse(value) == null) {
                    return "Принимаются только цифры.";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Yuk qayerdan keladi',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              ...kProductSources.map((code) {
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(productSourceLabel(code)),
                  value: _selectedSources.contains(code),
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true) {
                        _selectedSources.add(code);
                      } else {
                        _selectedSources.remove(code);
                      }
                    });
                  },
                );
              }),
              const SizedBox(height: 8),
              const Text(
                'Qaysi skladdan buyurtma bera oladi',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ..._skladOptions.entries.map((entry) {
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value),
                  value: _selectedSklads.contains(entry.key),
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true) {
                        _selectedSklads.add(entry.key);
                      } else {
                        _selectedSklads.remove(entry.key);
                      }
                    });
                  },
                );
              }),
            ],
            // Тех карта (состав) endi bu sahifada KO'RSATILMAYDI — u alohida
            // sahifada (ro'yxatda double-tap yoki «i» ikona) tahrirlanadi.
            // _techController saqlanadi: save'da mavjud tex karta o'zgarmay yuboriladi
            // va «Состав» avto-to'ldirishi shu controllerdan ishlaydi.
            const SizedBox(height: 24),
            Consumer<CategoryProviderAdminUpload>(
              builder: (context, uploadProvider, child) {
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: uploadProvider.isUploading
                      ? null
                      : () async {
                          if (_formKey.currentState!.validate()) {
                            if (_selectedType == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Выберите тип')),
                              );
                              return;
                            }
                            if (_moneApp && _selectedFilials.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Выберите хотя бы одну ветку')),
                              );
                              return;
                            }
                            if (_bozor && _selectedSources.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Kamida bitta manba tanlang')),
                              );
                              return;
                            }
                            if (_bozor && _selectedSklads.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Выберите хотя бы один склад')),
                              );
                              return;
                            }

                            String? imageUrl = _currentImageUrl;

                            // Upload new image if changed
                            if (_imageChanged && _selectedImage != null) {
                              final uploadedUrl = await uploadProvider
                                  .uploadImage(_selectedImage!);

                              if (uploadedUrl == null) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Произошла ошибка при загрузке изображения.')),
                                  );
                                }
                                return;
                              }
                              imageUrl = uploadedUrl;
                            } else if (_imageChanged &&
                                _selectedImage == null) {
                              // Image was removed
                              imageUrl = '';
                            }

                            if (!context.mounted) return;

                            final updatedProduct = widget.product.copyWith(
                              name: _nameController.text,
                              categoryName: companyController.text,
                              // Bo'sh maydonda double.parse('') FormatException
                              // otib saqlashni jimgina to'xtatardi (validator
                              // bo'sh qiymatga ruxsat beradi) — add ekranidagi
                              // kabi himoya qilamiz.
                              grams: grammControlle.text.isEmpty
                                  ? null
                                  : double.parse(grammControlle.text),
                              bozorGrams: bozorGrammController.text.isEmpty
                                  ? null
                                  : double.parse(bozorGrammController.text),
                              categoryId: _selectedCategoryId,
                              companyName: companyController.text,
                              type: _selectedType!,
                              ingredients: ingredientsController.text,
                              filials: _selectedFilials,
                              imageUrl: imageUrl,
                              moneApp: _moneApp,
                              bozor: _bozor,
                              // Kanonik tartibda; source = sources.first
                              // (model o'zi hisoblaydi). Bo'sh bo'lsa
                              // (bozor o'chiq) — eski manbalar qoladi.
                              sources: _selectedSources.isEmpty
                                  ? widget.product.sources
                                  : canonicalProductSources(_selectedSources),
                              sklads: _selectedSklads,
                              techCard: _techController.build(),
                              comment: _compositionAsIngredients
                                  ? _savedComment
                                  : ingredientsController.text,
                              compositionAsIngredients:
                                  _compositionAsIngredients,
                              wasteBase: _wasteApplies && _wasteValid
                                  ? _wasteBaseVal
                                  : 0,
                              wasteAmount: _wasteApplies && _wasteValid
                                  ? _wasteAmountVal
                                  : 0,
                              isSemiFinished: _isSemiFinished,
                              pieceWeightG: _pieceWeightApplies
                                  ? _pieceWeightVal
                                  : 0,
                            );

                            final success = await context
                                .read<ProductProviderAdmin>()
                                .updateProduct(updatedProduct);

                            if (success && context.mounted) {
                              // true qaytaramiz -> ro'yxat backenddan qayta
                              // yuklanadi (bozor/mone_app toggle'lar yangilanadi).
                              Navigator.pop(context, true);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Продукт обновлен')),
                              );
                            }
                          }
                        },
                  child: uploadProvider.isUploading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Обновлять', style: TextStyle(fontSize: 16)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    ingredientsController.dispose();
    grammControlle.dispose();
    bozorGrammController.dispose();
    wasteBaseController.dispose();
    wasteAmountController.dispose();
    pieceWeightController.dispose();
    _techController.dispose();
    super.dispose();
  }
}
