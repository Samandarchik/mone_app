// admin/ui/admin_add_product_ui.dart — yangi mahsulot qo'shish formasi
// (AddProductPage): ProductProviderAdmin.createProduct; kategoriya/filial
// CategoryProviderAdmin/FilialProviderAdmin, rasm CategoryProviderAdminUpload.
// Тип radiosi, mone/bozor, tozalash yo'qotishi, полуфабрикат, tex karta (TechCardController).
import 'dart:io';
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
import 'package:uz_ai_dev/core/data/sklad_registry.dart';
import 'package:uz_ai_dev/core/utils/product_sources.dart';

class AddProductPage extends StatefulWidget {
  // Ixtiyoriy oldindan to'ldirish: kategoriya ichidan ochilganda (masalan
  // shef → Полуфабрикат → Biskvit → Krem) kategoriya tanlangan va «пф»
  // yoqilgan holda ochiladi.
  final int? initialCategoryId;
  final bool initialSemiFinished;

  const AddProductPage({
    super.key,
    this.initialCategoryId,
    this.initialSemiFinished = false,
  });

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  // «пф» oldindan yoqilgan bo'lsa — switch'dagidek odatiy birlik «шт».
  late String? _selectedType = widget.initialSemiFinished ? 'шт' : null;
  final ingredientsControlle = TextEditingController();
  final grammController = TextEditingController(text: '1');
  final bozorGrammController = TextEditingController();
  // Tozalash yo'qotishi (faqat кг/л oilasida ko'rinadi), butun gramm.
  final wasteBaseController = TextEditingController();
  final wasteAmountController = TextEditingController();
  // «1 шт og'irligi» (gramm) — faqat xom шт mahsulotda ko'rinadi
  // (pf og'irligi o'z tex kartasidan olinadi).
  final pieceWeightController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  late int? _selectedCategoryId = widget.initialCategoryId;
  final List<int> _selectedFilials = [];
  File? _selectedImage;

  // Ombor → yuk keltiruvchi oqimi uchun yangi maydonlar
  bool _moneApp = true;
  bool _bozor = false;
  // Yuk qayerdan keladi — bir nechta manba tanlanishi mumkin
  // (Samarqand + Toshkent). Yangi mahsulotda standart: Samarqand.
  final Set<String> _selectedSources = {kDefaultProductSource};
  final List<int> _selectedSklads = [];

  // Полуфабрикат (masalan «Классик бисквит») — ishlab chiqariladi,
  // sotilmaydi; boshqa tex kartalarda ingredient bo'ladi.
  late bool _isSemiFinished = widget.initialSemiFinished;

  // Tarkib (tex karta)
  final TechCardController _techController = TechCardController();

  // «Состав» switch: yoniq bo'lsa Состав tarkib nomlaridan to'ladi (read-only),
  // eski erkin matn _savedComment ga saqlanadi.
  bool _compositionAsIngredients = false;
  String _savedComment = '';

  // Skladlar — SkladRegistry (superadmin serverda tahrirlaydi).
  Map<int, String> get _skladOptions => SkladRegistry.names;

  @override
  void initState() {
    super.initState();
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
        _savedComment = ingredientsControlle.text;
        _compositionAsIngredients = true;
        ingredientsControlle.text = _compositionNames();
      } else {
        // O'CHIQ: comment dagi eski matnni tiklaymiz.
        _compositionAsIngredients = false;
        ingredientsControlle.text = _savedComment;
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
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора изображения: $e')),
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
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при фотосъемке: $e')),
        );
      }
    }
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Выбор изображения'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Из галереи'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Из камеры'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новый продукт'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Image picker section
            GestureDetector(
              onTap: _showImageSourceDialog,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[200],
                ),
                child: _selectedImage != null
                    ? Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              _selectedImage!,
                              width: double.infinity,
                              height: 200,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: CircleAvatar(
                              backgroundColor: Colors.red,
                              child: IconButton(
                                icon: const Icon(Icons.close,
                                    color: Colors.white),
                                onPressed: () {
                                  setState(() {
                                    _selectedImage = null;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate,
                              size: 50, color: Colors.grey[600]),
                          const SizedBox(height: 8),
                          Text(
                            'Выбор изображения',
                            style: TextStyle(color: Colors.grey[600]),
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
              controller: ingredientsControlle,
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
              validator: (value) {
                if (!_compositionAsIngredients &&
                    (value == null || value.isEmpty)) {
                  return 'Писать Состав';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: grammController,
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
                if (double.tryParse(value) == null) {
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
                  // Oldindan berilgan kategoriya ro'yxatda bo'lsagina
                  // (aks holda Dropdown assert bilan yiqiladi).
                  initialValue: provider.categories
                          .any((c) => c.id == _selectedCategoryId)
                      ? _selectedCategoryId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Kategoriya',
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
                      _selectedCategoryId = value;
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Выберите категорию';
                    }
                    return null;
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
                        'Выберите филиалы:',
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
            // Тех карта (состав) bu sahifada KO'RSATILMAYDI — mahsulot
            // yaratilgach, ro'yxatda double-tap yoki «i» ikona orqali qo'shiladi.
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

                            String? imageUrl;

                            // Upload image if selected
                            if (_selectedImage != null) {
                              imageUrl = await uploadProvider
                                  .uploadImage(_selectedImage!);

                              if (imageUrl == null) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Произошла ошибка при загрузке изображения.')),
                                  );
                                }
                                return;
                              }
                            }

                            if (!context.mounted) return;

                            final product = ProductModelAdmin(
                              id: 0,
                              name: _nameController.text,
                              categoryId: _selectedCategoryId!,
                              type: _selectedType!,
                              categoryName: '',
                              grams: grammController.text.isEmpty
                                  ? null
                                  : double.parse(grammController.text),
                              bozorGrams: bozorGrammController.text.isEmpty
                                  ? null
                                  : double.parse(bozorGrammController.text),
                              ingredients: ingredientsControlle.text,
                              filials: _selectedFilials,
                              filialNames: [],
                              imageUrl: imageUrl ?? '',
                              moneApp: _moneApp,
                              bozor: _bozor,
                              // Kanonik tartibda; source = sources.first
                              // (model o'zi hisoblaydi). Bo'sh bo'lsa
                              // (bozor o'chiq) — standart Samarqand.
                              sources:
                                  canonicalProductSources(_selectedSources),
                              sklads: _selectedSklads,
                              techCard: _techController.build(),
                              comment: _compositionAsIngredients
                                  ? _savedComment
                                  : ingredientsControlle.text,
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
                                .createProduct(product);

                            if (success && context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Продукт добавлен')),
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
                      : const Text('Сохранять', style: TextStyle(fontSize: 16)),
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
    ingredientsControlle.dispose();
    grammController.dispose();
    bozorGrammController.dispose();
    wasteBaseController.dispose();
    wasteAmountController.dispose();
    pieceWeightController.dispose();
    _techController.dispose();
    super.dispose();
  }
}
