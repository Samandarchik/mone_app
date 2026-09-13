// admin/ui/dealog.dart — kategoriya yaratish/tahrirlash dialogi (CategoryDialog):
// CategoryProviderAdminUpload orqali create/update (rasm yuklash bilan).
// admin_add_categoriy.dart shu dialogni «+» va tahrirda chaqiradi.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/category_model.dart';
import 'package:uz_ai_dev/admin/provider/upload_image_provider.dart';
import 'package:uz_ai_dev/admin/services/print_agent_service.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';

class CategoryDialog extends StatefulWidget {
  final CategoryProductAdmin? category;

  const CategoryDialog({super.key, this.category});

  @override
  State<CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _printController;
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  // Printer tanlash: agentlar ro'yxati serverdan (real Windows printer nomlari).
  // Tanlov "agent\u0000printer" kalit ko'rinishida; null = Standart.
  List<PrintAgentInfo>? _agents;
  bool _agentsLoading = true;
  String? _printerKey;

  bool get isEditing => widget.category != null;

  static String? _keyOf(String? agent, String? printer) {
    if (agent == null || agent.isEmpty) return null;
    return '$agent\u0000${printer ?? ''}';
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _printController = TextEditingController(
      text: widget.category?.printerId.toString() ?? '1',
    );
    _printerKey =
        _keyOf(widget.category?.printerAgent, widget.category?.printerName);
    _loadAgents();
  }

  Future<void> _loadAgents() async {
    try {
      final agents = await PrintAgentService().getPrintAgents();
      if (mounted) {
        setState(() {
          _agents = agents;
          _agentsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _agentsLoading = false);
    }
  }

  // Dropdown bandlari: har agent uchun "(standart printer)" + real printerlari.
  // Saqlangan tanlov ro'yxatda bo'lmasa ham ko'rsatiladi (agent oflayn bo'lsa).
  List<DropdownMenuItem<String?>> _printerItems() {
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem(value: null, child: Text('Стандарт')),
    ];
    final seen = <String>{};
    for (final agent in _agents ?? <PrintAgentInfo>[]) {
      final suffix = agent.connected ? '' : ' (offline)';
      final defKey = _keyOf(agent.name, '')!;
      seen.add(defKey);
      items.add(DropdownMenuItem(
        value: defKey,
        child: Text('${agent.name}: standart printer$suffix',
            overflow: TextOverflow.ellipsis),
      ));
      for (final printer in agent.printers) {
        final key = _keyOf(agent.name, printer)!;
        if (!seen.add(key)) continue;
        items.add(DropdownMenuItem(
          value: key,
          child: Text('${agent.name}: $printer$suffix',
              overflow: TextOverflow.ellipsis),
        ));
      }
    }
    if (_printerKey != null && !seen.contains(_printerKey)) {
      final (agent, printer) = _splitKey(_printerKey!);
      items.add(DropdownMenuItem(
        value: _printerKey,
        child: Text(
            '$agent: ${printer.isEmpty ? 'standart printer' : printer} (?)',
            overflow: TextOverflow.ellipsis),
      ));
    }
    return items;
  }

  // Kalit "agent\u0000printer" — NUL ajratgich nomlarda uchramaydi.
  static (String, String) _splitKey(String key) {
    final idx = key.indexOf('\u0000');
    if (idx < 0) return (key, '');
    return (key.substring(0, idx), key.substring(idx + 1));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _printController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (image != null) {
      if (!mounted) return;
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final provider = context.read<CategoryProviderAdminUpload>();
    bool success;

    final (agent, printer) =
        _printerKey == null ? ('', '') : _splitKey(_printerKey!);

    if (isEditing) {
      success = await provider.updateCategory(
        widget.category!,
        newName: _nameController.text.trim(),
        newPrint: int.parse(_printController.text),
        newPrinterAgent: agent,
        newPrinterName: printer,
        imageFile: _selectedImage,
      );
    } else {
      success = await provider.createCategory(
        CategoryProductAdmin(
          id: 0,
          name: _nameController.text.trim(),
          printerId: int.parse(_printController.text),
          printerAgent: agent,
          printerName: printer,
          imageUrl: null,
        ),
        imageFile: _selectedImage,
      );
    }

    if (mounted) {
      setState(() => _isLoading = false);

      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing ? 'Category updated' : 'Category created'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.error ?? 'Operation failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isEditing ? 'Редактировать категорию' : 'Создать категорию',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: _selectedImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              _selectedImage!,
                              fit: BoxFit.cover,
                            ),
                          )
                        // Rasm manzili BO'SH SATR ham bo'lishi mumkin (пф
                        // kategoriyalarida `image_url: ""`) — u holda tarmoqqa
                        // chiqmaymiz, aks holda baseUrl'ning o'zi so'ralib
                        // «Invalid image data» xatosi chiqadi.
                        : (widget.category?.imageUrl?.isNotEmpty ?? false)
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AppNetworkImage(
                                  imageUrl:
                                      "${AppUrls.baseUrl}${widget.category!.imageUrl!}",
                                  fit: BoxFit.cover,
                                  errorWidget: (context) => Icon(
                                    Icons.broken_image,
                                    size: 48,
                                    color: Colors.grey[400],
                                  ),
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate,
                                      size: 48, color: Colors.grey[400]),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Нажмите, чтобы выбрать изображение',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Название категории',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Пожалуйста, введите название категории';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Printer: ulangan agentlardagi real printer nomlaridan tanlanadi.
                // "Стандарт" — backend o'zi hal qiladi (default agent + default
                // printer). Ro'yxat kelmasa saqlangan qiymat bilan ko'rinadi.
                DropdownButtonFormField<String?>(
                  initialValue: _printerKey,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Принтер',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.print),
                    suffixIcon: _agentsLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  items: _printerItems(),
                  onChanged: (value) => setState(() => _printerKey = value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _printController,
                  decoration: const InputDecoration(
                    labelText: 'Группа чека (номер)',
                    helperText:
                        'Одинаковый номер — один чек, разные — отдельные чеки',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.receipt_long),
                  ),
                  keyboardType: TextInputType.numberWithOptions(),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Пожалуйста, введите значение для печати';
                    }
                    if (int.tryParse(value) == null) {
                      return 'Пожалуйста, введите действительный номер';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                Consumer<CategoryProviderAdminUpload>(
                  builder: (context, provider, child) {
                    if (provider.isUploading) {
                      return Column(
                        children: [
                          LinearProgressIndicator(
                            value: provider.uploadProgress,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Загрузка изображения... ${(provider.uploadProgress * 100).toInt()}%',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _isLoading ? null : () => Navigator.pop(context),
                        child: const Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator.adaptive(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(isEditing ? 'Обновлять' : 'Создавать'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
