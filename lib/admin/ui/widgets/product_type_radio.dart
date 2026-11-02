// admin/ui/widgets/product_type_radio.dart — тех карта editori sub-vidjeti:
// ProductTypeRadioGroup (birlik tanlash radio) + kProductTypeOptions kanonik
// 9 birlik ro'yxati + normalizeProductType (eski qiymatlarni to'g'rilash).
import 'package:flutter/material.dart';

import 'package:uz_ai_dev/core/catalog/product_unit.dart';
export 'package:uz_ai_dev/core/catalog/product_unit.dart';

/// Тип (birlik) tanlovi — radio buttonlar bilan.
/// Ro'yxatda bo'lmagan eski qiymat kelsa, u ham variant sifatida ko'rsatiladi.
class ProductTypeRadioGroup extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const ProductTypeRadioGroup({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = List<String>.from(kProductTypeOptions);
    if (value != null && value!.isNotEmpty && !options.contains(value)) {
      options.add(value!);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'O‘lchov birligi',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        RadioGroup<String>(
          groupValue: value,
          onChanged: onChanged,
          child: Wrap(
            children: options.map((t) {
              return SizedBox(
                width: 120,
                child: RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(productUnitLabel(t)),
                  value: t,
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
