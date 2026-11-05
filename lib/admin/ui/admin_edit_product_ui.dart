import 'package:flutter/material.dart';
import 'package:uz_ai_dev/admin/ui/product_form_page.dart';
import 'package:uz_ai_dev/core/catalog/product.dart';

class EditProductPage extends StatelessWidget {
  const EditProductPage({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) => ProductFormPage(product: product);
}
