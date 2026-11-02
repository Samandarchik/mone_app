import 'package:flutter/material.dart';
import 'package:uz_ai_dev/admin/ui/product_form_page.dart';

/// Mavjud navigatsiya uchun kirish nuqtasi; forma qo'shish/tahrirlashga umumiy.
class AddProductPage extends StatelessWidget {
  const AddProductPage(
      {super.key, this.initialCategoryId, this.initialSemiFinished = false});

  final int? initialCategoryId;
  final bool initialSemiFinished;

  @override
  Widget build(BuildContext context) => ProductFormPage(
        initialCategoryId: initialCategoryId,
        initialSemiFinished: initialSemiFinished,
      );
}
