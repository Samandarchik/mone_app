// admin/ui/widgets/sale_price_dialog.dart — mahsulot SOTISH narxini qo'lda
// kiritishning YAGONA manbai: showSalePriceDialog (dialogning o'zi) va
// editProductSalePrice (dialog → ProductProviderAdmin orqali saqlash →
// snackbar). «Foyda nazorati», «Foyda analitikasi» va «POS menyu»
// ekranlaridagi «narx belgilanmagan» mahsulotlar shu orqali narxlanadi.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/catalog/tech_card.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/core/utils/money_input.dart';
import 'package:uz_ai_dev/production/ui/widgets/cost_sheet.dart'
    show fmtCostMoney;

// Sotish narxini kiritish dialogi. Natija: yangi narx (BUTUN so'm) yoki
// null (bekor qilindi). 0 — narxni belgilanmagan holatga qaytarish.
Future<int?> showSalePriceDialog(
  BuildContext context, {
  required String title,
  required int initial,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _SalePriceDialog(title: title, initial: initial),
  );
}

// To'liq oqim: mahsulotni topish → dialog → tex kartadagi sale_price ni
// saqlash → snackbar. Qaytaradi: saqlangan yangi narx yoki null (bekor
// qilindi / o'zgarmadi / xatolik) — chaqiruvchi shunga qarab ekranini
// yangilaydi.
//
// Narx `tech_card.sale_price` da saqlanadi. Tex kartasi YO'Q mahsulot
// (masalan non, ichimlik) uchun faqat narxni saqlaydigan bo'sh tex karta
// yaratiladi — bo'sh karta tarkibsiz bo'lgani uchun «Foyda nazorati»
// jadvaliga kirmaydi (techCardHasContent false).
Future<int?> editProductSalePrice(
  BuildContext context, {
  required int productId,
  required String productName,
}) async {
  final provider = context.read<ProductProviderAdmin>();
  final messenger = ScaffoldMessenger.of(context);

  // Mahsulotlar hali yuklanmagan bo'lishi mumkin (POS menyu ekrani o'z
  // servisidan ishlaydi) — yagona manbadan bir marta yuklaymiz.
  if (provider.products.isEmpty) {
    await provider.initializeProducts();
  }
  if (!context.mounted) return null;

  final product = provider.productById(productId);
  if (product == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Mahsulot topilmadi')),
    );
    return null;
  }

  final card = product.techCard;
  final current = card?.salePrice ?? 0;
  final price = await showSalePriceDialog(
    context,
    title: productName.isEmpty ? product.name : productName,
    initial: current,
  );
  if (price == null || price == current || !context.mounted) return null;

  final updated = product.copyWith(
    techCard: (card ?? const TechCard()).copyWith(salePrice: price),
  );
  final ok = await provider.updateProduct(updated);

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        ok
            ? (price > 0
                ? '${product.name}: narx ${fmtCostMoney(price)} qilib saqlandi'
                : '${product.name}: narx olib tashlandi')
            : provider.error ?? 'Saqlashda xatolik',
      ),
      backgroundColor: ok ? null : Colors.red,
    ),
  );
  return ok ? price : null;
}

// Pul — BUTUN so'm (tiyin yo'q, kasr kiritilmaydi).
class _SalePriceDialog extends StatefulWidget {
  final String title;
  final int initial;

  const _SalePriceDialog({required this.title, required this.initial});

  @override
  State<_SalePriceDialog> createState() => _SalePriceDialogState();
}

class _SalePriceDialogState extends State<_SalePriceDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial > 0 ? formatMoneyInput(widget.initial) : '',
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, parseMoney(_ctrl.text));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        // Yozayotganda har 3 xonadan probel: 200 000.
        inputFormatters: [ThousandsSeparatorInputFormatter()],
        decoration: const InputDecoration(
          labelText: 'Sotish narxi (1 dona)',
          suffixText: ' сум',
          hintText: '—',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Bekor'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Saqlash')),
      ],
    );
  }
}
