// admin/ui/user_edit_dialog.dart — foydalanuvchi yaratish/tahrirlash dialogi
// (UserEditDialog): UserManagementService orqali create/update; rol tanlovi
// seller/ombor/yuk_keltiruvchi/bugalter/shef.
// HR loyihasidagi users_screen dialog uslubida. Biznes-logika to'liq
// eski EditUserPage (edit_user_list.dart) dan ko'chirilgan:
//   - telefon + parol majburiy (ism ixtiyoriy — bo'sh qolsa telefon yoziladi)
//   - rol tanlovi: seller/ombor/yuk_keltiruvchi/bugalter/shef
//   - seller → filial (majburiy); ombor/shef → bitta sklad;
//     yuk_keltiruvchi → bir nechta sklad + manbalar (sources)
//   - ombor → Telegram guruh ID (ixtiyoriy)
//   - bugalter → kategoriya so'ralmaydi (bo'sh ro'yxat yuboriladi)
//   - shef → «Тех карта kategoriyalari» chiplari (sotuvchidagi kabi
//     User.categoryIds = category_list): shef FAQAT shu kategoriyalarning
//     тех картасини ko'radi va tahrirlaydi. Bo'sh — hech narsa ko'rinmaydi.
//   - seller → «Ostatka (SH5) omborlari» ruxsati (kategoriya chiplari naqshi):
//     tanlangan omborlarni sotuvchi ilovada ochib ko'radi va smena
//     topshiradi/qabul qiladi (User.sh5Sklads)
//   - create → POST /api/register, edit → PUT /api/users/{id}
//     (edit'da ism/parol faqat bo'sh bo'lmaganda yuboriladi)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/sh5_remain_model.dart';
import 'package:uz_ai_dev/admin/model/user_model.dart';
import 'package:uz_ai_dev/admin/services/sh5_service.dart';
import 'package:uz_ai_dev/admin/services/user_management_service.dart';
import 'package:uz_ai_dev/core/constants/roles.dart';
import 'package:uz_ai_dev/user/provider/provider.dart';
import 'package:uz_ai_dev/core/data/sklad_registry.dart';

class UserEditDialog extends StatefulWidget {
  final User? user;

  const UserEditDialog({super.key, this.user});

  @override
  State<UserEditDialog> createState() => _UserEditDialogState();
}

class _UserEditDialogState extends State<UserEditDialog> {
  final _formKey = GlobalKey<FormState>();
  final UserManagementService _userService = UserManagementService();
  final FilialService _filialService = FilialService();
  final Sh5Service _sh5Service = Sh5Service();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _passwordController;
  late TextEditingController _telegramGroupController;

  int? _selectedFilialId;
  List<int> _selectedSklads = [];
  List<String> _selectedSources = [];
  String _selectedRole = AppRoles.seller;
  late List<String> _roleOptions;

  // Ombor roli uchun filiallar o'rniga ko'rsatiladigan skladlar — SkladRegistry
  // (superadmin serverda tahrirlaydi).
  Map<int, String> get _skladOptions => SkladRegistry.names;
  // Yuk keltiruvchi roli uchun mahsulot manbalari (kategoriya o'rniga).
  static const Map<String, String> _sourceOptions = {
    'samarqand': 'Samarqand',
    'toshkent': 'Toshkent',
    'zagranitsa': 'Zagranitsa',
  };

  bool _isSaving = false;
  // true — _loadFilials post-frame'da boshlanguncha birinchi freymda
  // "filial yo'q" ko'rinib qolmasligi uchun.
  bool _isLoadingFilials = true;
  bool _obscurePassword = true;

  List<Filial> _filials = [];
  List<int> _categoryIds = [];
  String _filialError = '';

  // Ostatka (SH5) omborlari — admin ro'yxati va tanlangan ruxsatlar.
  List<Sh5RemainSklad> _sh5Sklads = [];
  List<int> _selectedSh5Sklads = [];
  bool _sh5Loading = true;
  String _sh5Error = '';

  static const Color _accent = Color(0xFF3699ff);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user?.name ?? '');
    _phoneController = TextEditingController(text: widget.user?.phone ?? '');
    _passwordController = TextEditingController();
    _telegramGroupController =
        TextEditingController(text: widget.user?.telegramGroupId ?? '');
    // filial_id 0 (filial belgilanmagan, masalan ombor/yuk keltiruvchi) -> null,
    // aks holda Dropdown mos element topolmay crash bo'ladi.
    final fid = widget.user?.filial?.id ?? widget.user?.filialId;
    _selectedFilialId = (fid == null || fid == 0) ? null : fid;
    _selectedSklads = List.from(widget.user?.sklads ?? []);
    _selectedSources = List.from(widget.user?.sources ?? []);
    _categoryIds = List.from(widget.user?.categoryIds ?? []);
    _selectedSh5Sklads = List.from(widget.user?.sh5Sklads ?? []);

    // Rol tanlovi. Standart rollar + agar userning roli ulardan boshqa bo'lsa
    // (masalan superadmin) uni ham ro'yxatga qo'shamiz (chip yo'qolib qolmasligi uchun).
    _roleOptions = [
      AppRoles.seller,
      AppRoles.ombor,
      AppRoles.yukKeltiruvchi,
      AppRoles.bugalter,
      AppRoles.shef,
    ];
    final r = widget.user?.role ?? AppRoles.seller;
    _selectedRole = r.isEmpty ? AppRoles.seller : r;
    if (!_roleOptions.contains(_selectedRole)) {
      _roleOptions = [_selectedRole, ..._roleOptions];
    }

    // Provider/setState darhol notify qiladi; initState build fazasida —
    // "markNeedsBuild called during build" bo'lmasligi uchun keyingi freymga.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadFilials();
      _loadCategories();
      _loadSh5Sklads();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _telegramGroupController.dispose();
    super.dispose();
  }

  String _roleLabel(String role) {
    switch (role) {
      case AppRoles.seller:
        return 'Sotuvchi';
      case AppRoles.ombor:
        return 'Ombor';
      case AppRoles.yukKeltiruvchi:
        return 'Yuk keltiruvchi';
      case AppRoles.bugalter:
        return 'Bugalter';
      case AppRoles.shef:
        return 'Shef';
      case AppRoles.superAdmin:
        return 'Superadmin';
      case AppRoles.admin:
        return 'Admin';
      default:
        return role;
    }
  }

  Future<void> _loadFilials() async {
    setState(() {
      _isLoadingFilials = true;
      _filialError = '';
    });
    try {
      final filials = await _filialService.getAllFilials();
      if (!mounted) return;
      setState(() {
        _filials = filials;
        _isLoadingFilials = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _filialError = e.toString();
        _isLoadingFilials = false;
      });
    }
  }

  // Ostatka omborlari ro'yxati (admin so'raganda hammasi keladi).
  Future<void> _loadSh5Sklads() async {
    setState(() {
      _sh5Loading = true;
      _sh5Error = '';
    });
    try {
      final list = await _sh5Service.fetchSklads();
      if (!mounted) return;
      setState(() {
        _sh5Sklads = list;
        _sh5Loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sh5Error = e.toString();
        _sh5Loading = false;
      });
    }
  }

  Future<void> _loadCategories() async {
    final provider = Provider.of<ProductProvider>(context, listen: false);
    if (provider.categories.isEmpty) {
      await provider.fetchCategories();
    }
  }

  // Rolga qarab filial/sklad tanlovini tekshiradi.
  // Xato bo'lsa snackbar chiqarib true qaytaradi (saqlashni to'xtatish uchun).
  bool _hasFilialSkladError() {
    String? message;
    if (_selectedRole == AppRoles.seller) {
      if (_selectedFilialId == null) {
        message = 'Filialni tanlang';
      }
    } else if (_selectedRole == AppRoles.ombor ||
        _selectedRole == AppRoles.shef) {
      // Shef ham ombor kabi bitta sklad bilan ishlaydi (filial talab qilinmaydi).
      if (_selectedSklads.length != 1) {
        message = 'Bitta sklad tanlang';
      }
    } else if (_selectedRole == AppRoles.yukKeltiruvchi) {
      if (_selectedSklads.isEmpty) {
        message = 'Kamida bitta sklad tanlang';
      }
    }
    // bugalter: filial ham, sklad ham talab qilinmaydi.
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return true;
    }
    return false;
  }

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) return;
    if (_hasFilialSkladError()) return;

    // filial_id faqat seller uchun yuboriladi; boshqa rollar uchun null.
    final int? filialId =
        _selectedRole == AppRoles.seller ? _selectedFilialId : null;

    // Bugalter kategoriya bilan cheklanmaydi — bo'sh ro'yxat yuboriladi,
    // rol almashtirilganda eski tanlov qolib ketmasligi uchun.
    // Shef uchun esa category_list — тех карта ruxsati (sotuvchidagi kabi).
    final List<int> categoryIds =
        _selectedRole == AppRoles.bugalter ? [] : _categoryIds;

    // Ostatka ruxsati FAQAT sotuvchi uchun; rol almashtirilsa eski tanlov
    // qolib ketmasligi uchun bo'sh ro'yxat yuboriladi.
    final List<int> sh5Sklads =
        _selectedRole == AppRoles.seller ? _selectedSh5Sklads : [];

    setState(() => _isSaving = true);

    try {
      if (widget.user != null) {
        // Mavjud foydalanuvchini yangilash - PUT /api/users/{id}
        final request = UpdateUserRequest(
          // Bo'sh qoldirilsa eski ism saqlanadi (kalit yuborilmaydi).
          name: _nameController.text.trim().isNotEmpty
              ? _nameController.text.trim()
              : null,
          phone: _phoneController.text.trim(),
          isAdmin: widget.user!.isAdmin,
          role: _selectedRole,
          filialId: filialId,
          // Parol faqat kiritilganda yuboriladi (bo'sh — eski parol qoladi).
          password: _passwordController.text.isNotEmpty
              ? _passwordController.text
              : null,
          categoryIds: categoryIds,
          sklads: _selectedSklads,
          sh5Sklads: sh5Sklads,
          // sources faqat yuk_keltiruvchi roli uchun yuboriladi;
          // boshqa rollarda kalit yuborilmaydi (backenddagi qiymat saqlanadi).
          sources: _selectedRole == AppRoles.yukKeltiruvchi
              ? _selectedSources
              : null,
          telegramGroupId: _telegramGroupController.text.trim(),
        );
        await _userService.updateUser(widget.user!.id, request);
      } else {
        // Yangi foydalanuvchi yaratish - POST /api/register
        final request = CreateUserRequest(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          password: _passwordController.text,
          isAdmin: false,
          role: _selectedRole,
          filialId: filialId,
          categoryIds: categoryIds,
          sklads: _selectedSklads,
          sh5Sklads: sh5Sklads,
          sources: _selectedRole == AppRoles.yukKeltiruvchi
              ? _selectedSources
              : null,
          telegramGroupId: _telegramGroupController.text.trim(),
        );
        await _userService.createUser(request);
      }

      if (mounted) {
        // true — o'zgarish bo'ldi; ekran ro'yxatni yangilaydi.
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  InputDecoration _deco(String label, {String? hint, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.grey[700],
      ),
    );
  }

  // Rol — bitta tanlanadigan FilterChip'lar (birini tanlash boshqasini bekor qiladi).
  Widget _buildRoleChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Rol'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _roleOptions.map((role) {
            final sel = _selectedRole == role;
            return FilterChip(
              label: Text(
                _roleLabel(role),
                style: TextStyle(fontSize: 12, color: sel ? Colors.white : null),
              ),
              selected: sel,
              onSelected: (v) {
                if (!v || role == _selectedRole) return;
                setState(() {
                  _selectedRole = role;
                  // Rol o'zgarsa filial/sklad tanlovi boshqa ro'yxatga o'tadi,
                  // eski qiymat mos kelmasligi mumkin — tozalaymiz.
                  _selectedFilialId = null;
                  _selectedSklads = [];
                });
              },
              selectedColor: _accent,
              checkmarkColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            );
          }).toList(),
        ),
      ],
    );
  }

  // Seller uchun filial tanlovi (majburiy).
  Widget _buildFilialSelector() {
    if (_isLoadingFilials) {
      return InputDecorator(
        decoration: _deco('Filial'),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Filiallar yuklanmoqda...', style: TextStyle(fontSize: 14)),
          ],
        ),
      );
    }
    if (_filialError.isNotEmpty) {
      return InputDecorator(
        decoration: _deco('Filial'),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade600, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Filiallar yuklanmadi',
                style: TextStyle(fontSize: 13, color: Colors.red),
              ),
            ),
            TextButton(
              onPressed: _loadFilials,
              child: const Text('Qayta urinish'),
            ),
          ],
        ),
      );
    }
    final int? dropdownValue = (_selectedFilialId != null &&
            _filials.any((f) => f.id == _selectedFilialId))
        ? _selectedFilialId
        : null;
    return DropdownButtonFormField<int>(
      initialValue: dropdownValue,
      decoration: _deco('Filial'),
      isExpanded: true,
      hint: const Text('Filialni tanlang'),
      items: _filials
          .map((f) => DropdownMenuItem<int>(
                value: f.id,
                child: Text(f.name, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (value) => setState(() => _selectedFilialId = value),
    );
  }

  // Rolga qarab sklad tanlovi:
  // - ombor / shef    → bitta sklad (radio)
  // - yuk_keltiruvchi → bir nechta sklad (checkbox)
  Widget _buildSkladSelector() {
    final bool isSingle =
        _selectedRole == AppRoles.ombor || _selectedRole == AppRoles.shef;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(isSingle ? 'Sklad' : 'Skladlar'),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD1D5DB)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: isSingle
              ? RadioGroup<int>(
                  groupValue:
                      _selectedSklads.isNotEmpty ? _selectedSklads.first : null,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedSklads = [value];
                      });
                    }
                  },
                  child: Column(
                    children: [
                      for (final entry in _skladOptions.entries)
                        RadioListTile<int>(
                          value: entry.key,
                          title: Text(entry.value,
                              style: const TextStyle(fontSize: 14)),
                          activeColor: _accent,
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                        ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    for (final entry in _skladOptions.entries)
                      CheckboxListTile(
                        value: _selectedSklads.contains(entry.key),
                        title: Text(entry.value,
                            style: const TextStyle(fontSize: 14)),
                        activeColor: _accent,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              if (!_selectedSklads.contains(entry.key)) {
                                _selectedSklads.add(entry.key);
                              }
                            } else {
                              _selectedSklads.remove(entry.key);
                            }
                          });
                        },
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  // Yuk keltiruvchi uchun "Yuk qayerdan keladi" tanlovi (kategoriya o'rniga).
  // Hech biri tanlanmasa — cheklov yo'q, hammasini ko'radi.
  Widget _buildSourceChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Yuk qayerdan keladi'),
        const SizedBox(height: 4),
        Text(
          'Tanlanmasa hammasi ko\'rinadi',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _sourceOptions.entries.map((entry) {
            final sel = _selectedSources.contains(entry.key);
            return FilterChip(
              label: Text(
                entry.value,
                style: TextStyle(fontSize: 12, color: sel ? Colors.white : null),
              ),
              selected: sel,
              onSelected: (v) {
                setState(() {
                  if (v) {
                    if (!_selectedSources.contains(entry.key)) {
                      _selectedSources.add(entry.key);
                    }
                  } else {
                    _selectedSources.remove(entry.key);
                  }
                });
              },
              selectedColor: _accent,
              checkmarkColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            );
          }).toList(),
        ),
      ],
    );
  }

  // Kategoriya tanlovi (bugalterdan boshqa rollar uchun).
  // Sotuvchida — katalog ruxsati; shefda — тех карта ruxsati (bir xil
  // `category_list` maydoni, faqat sarlavha/izoh rolga moslanadi).
  Widget _buildCategoryChips() {
    final bool isShef = _selectedRole == AppRoles.shef;
    return Consumer<ProductProvider>(
      builder: (context, provider, child) {
        Widget body;
        if (provider.isLoading) {
          body = const Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Kategoriyalar yuklanmoqda...',
                  style: TextStyle(fontSize: 13)),
            ],
          );
        } else if (provider.errorMessage != null) {
          body = Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade600, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Kategoriyalar yuklanmadi',
                  style: TextStyle(fontSize: 13, color: Colors.red),
                ),
              ),
              TextButton(
                onPressed: _loadCategories,
                child: const Text('Qayta urinish'),
              ),
            ],
          );
        } else if (provider.categories.isEmpty) {
          body = Text(
            'Kategoriyalar topilmadi',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          );
        } else {
          body = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: provider.categories.map((category) {
              final sel = _categoryIds.contains(category.id);
              return FilterChip(
                label: Text(
                  category.name,
                  style:
                      TextStyle(fontSize: 12, color: sel ? Colors.white : null),
                ),
                selected: sel,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      if (!_categoryIds.contains(category.id)) {
                        _categoryIds.add(category.id);
                      }
                    } else {
                      _categoryIds.remove(category.id);
                    }
                  });
                },
                selectedColor: _accent,
                checkmarkColor: Colors.white,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              );
            }).toList(),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(
                isShef ? 'Тех карта kategoriyalari' : 'Kategoriyalar'),
            if (isShef) ...[
              const SizedBox(height: 4),
              Text(
                'Shef faqat belgilangan kategoriyalarning тех картасини '
                'ko\'radi va tahrirlaydi. Bo\'sh qoldirilsa — hech narsa '
                'ko\'rinmaydi.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 8),
            body,
          ],
        );
      },
    );
  }

  // Ostatka (SH5) ombor ruxsati — sotuvchi uchun (kategoriya chiplari naqshi).
  // Tanlanmasa sotuvchi «Ostatka» ekranini umuman ko'rmaydi.
  Widget _buildSh5Chips() {
    Widget body;
    if (_sh5Loading) {
      body = const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Omborlar yuklanmoqda...', style: TextStyle(fontSize: 13)),
        ],
      );
    } else if (_sh5Error.isNotEmpty) {
      body = Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade600, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Omborlar yuklanmadi',
              style: TextStyle(fontSize: 13, color: Colors.red),
            ),
          ),
          TextButton(
            onPressed: _loadSh5Sklads,
            child: const Text('Qayta urinish'),
          ),
        ],
      );
    } else if (_sh5Sklads.isEmpty) {
      body = Text(
        'Ombor topilmadi (StoreHouse hali qoldiq yubormagan)',
        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
      );
    } else {
      body = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _sh5Sklads.map((s) {
          final sel = _selectedSh5Sklads.contains(s.id);
          return FilterChip(
            label: Text(
              s.name,
              style: TextStyle(fontSize: 12, color: sel ? Colors.white : null),
            ),
            selected: sel,
            onSelected: (v) {
              setState(() {
                if (v) {
                  if (!_selectedSh5Sklads.contains(s.id)) {
                    _selectedSh5Sklads.add(s.id);
                  }
                } else {
                  _selectedSh5Sklads.remove(s.id);
                }
              });
            },
            selectedColor: _accent,
            checkmarkColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          );
        }).toList(),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Ostatka (SH5) omborlari'),
        const SizedBox(height: 4),
        Text(
          'Tanlangan omborni sotuvchi ochib ko\'radi va smena topshiradi',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        body,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.user != null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(isEdit
          ? 'Foydalanuvchini tahrirlash'
          : 'Yangi foydalanuvchi'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Telefon (login) — majburiy.
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration:
                      _deco('Telefon raqam', hint: '+998901234567'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Telefon raqam majburiy';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                // Parol — yangi userda majburiy; tahrirda bo'sh qolsa o'zgarmaydi.
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: _deco(
                    isEdit ? 'Yangi parol (ixtiyoriy)' : 'Parol',
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (!isEdit && (value == null || value.isEmpty)) {
                      return 'Parol majburiy';
                    }
                    if (value != null && value.isNotEmpty && value.length < 2) {
                      return 'Parol kamida 2 ta belgidan iborat bo\'lishi kerak';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                // Ism — ixtiyoriy.
                TextFormField(
                  controller: _nameController,
                  decoration: _deco(
                    'Ism (ixtiyoriy — bo\'sh qolsa telefon yoziladi)',
                  ),
                ),
                const SizedBox(height: 16),

                _buildRoleChips(),
                const SizedBox(height: 16),

                // Filial (seller) yoki sklad (ombor / yuk_keltiruvchi / shef).
                if (_selectedRole == AppRoles.seller) ...[
                  _buildFilialSelector(),
                  const SizedBox(height: 16),
                ] else if (_selectedRole == AppRoles.ombor ||
                    _selectedRole == AppRoles.yukKeltiruvchi ||
                    _selectedRole == AppRoles.shef) ...[
                  _buildSkladSelector(),
                  const SizedBox(height: 16),
                ],

                // Telegram guruh ID (faqat ombor roli uchun, ixtiyoriy).
                if (_selectedRole == AppRoles.ombor) ...[
                  TextFormField(
                    controller: _telegramGroupController,
                    decoration:
                        _deco('Telegram guruh ID', hint: '-1001234567890'),
                  ),
                  const SizedBox(height: 16),
                ],

                // Yuk keltiruvchi: kategoriya o'rniga manba (source) tanlovi.
                // Bugalter: kategoriya so'ralmaydi.
                // Shef: kategoriya = тех карта ruxsati.
                // Boshqa rollar: kategoriya tanlovi (katalog).
                if (_selectedRole == AppRoles.yukKeltiruvchi)
                  _buildSourceChips()
                else if (_selectedRole != AppRoles.bugalter)
                  _buildCategoryChips(),

                // Ostatka (SH5) ruxsati — faqat sotuvchi uchun.
                if (_selectedRole == AppRoles.seller) ...[
                  const SizedBox(height: 16),
                  _buildSh5Chips(),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Bekor qilish'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _saveUser,
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Saqlash'),
        ),
      ],
    );
  }
}
