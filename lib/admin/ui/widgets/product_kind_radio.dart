// admin/ui/widgets/product_kind_radio.dart — mahsulot TURI tanlovi
// (ProductKindRadioGroup): Xomashyo / Полуфабрикат / Tayyor mahsulot.
// Admin add/edit formasida eski «Полуфабрикат» switch o'rnini bosadi;
// kanallar («Sotiladi» / «Sotib olinadi») turdan ALOHIDA switch'lar.
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/catalog/product.dart';

// Har tur uchun qisqa izoh (radio ostida).
String productKindHint(ProductKind kind) {
  switch (kind) {
    case ProductKind.raw:
      return 'Un, shakar, tuxum, qadoq... — sotib olinadi, ishlab chiqarilmaydi';
    case ProductKind.pf:
      return 'Biskvit, krem... — ishlab chiqariladi va retseptlarda sarflanadi; '
          'kataloglarda ko\'rinmaydi';
    case ProductKind.product:
      return 'Tort, pirojnoe... — retsept bo\'yicha ishlab chiqariladi va sotiladi';
  }
}

class ProductKindRadioGroup extends StatelessWidget {
  final ProductKind value;
  final ValueChanged<ProductKind> onChanged;

  const ProductKindRadioGroup({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Turi',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        RadioGroup<ProductKind>(
          groupValue: value,
          onChanged: (k) {
            if (k != null) onChanged(k);
          },
          child: Column(
            children: ProductKind.values.map((k) {
              return RadioListTile<ProductKind>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(k.label),
                subtitle: Text(
                  productKindHint(k),
                  style: const TextStyle(fontSize: 12),
                ),
                value: k,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
