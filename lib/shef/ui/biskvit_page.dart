// shef/ui/biskvit_page.dart — shef bosh menyusidagi «Biskvit» bo'limi
// (BiskvitPage): tepada biskvit rasmi (assets/biskvit.png), ostida to'rt
// bo'lim — Biskvit / Nachinka / Krem / Bezaklar.
// Har bo'lim backend'dagi MAVJUD oddiy kategoriyaga (Бисквит, Начинка, Крем,
// Украшения) NOMI bo'yicha bog'lanadi (_BiskvitSection.aliases — ruscha /
// lotincha, birlik / ko'plik). Bo'lim bosilsa ShefTechCardProductsPage —
// ya'ni «Тех карта»dagi o'sha kategoriya sahifasi, ichidagi hamma mahsulot
// va retseptlari bilan — ochiladi. Kategoriya topilmasa yaratiladi.
// Bu kategoriyalar «Тех карта» ro'yxatidan YASHIRILADI
// (isBiskvitCategoryName → shef_tech_card_page.dart): endi ular faqat shu yerda.
// Backend'da kategoriya ierarxiyasi yo'q — «Biskvit» guruhi faqat ilovada.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/category_model.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/provider/upload_image_provider.dart';
import 'package:uz_ai_dev/shef/ui/shef_tech_card_page.dart';

const Color _bgColor = Color(0xFFFAF6F1);
const Color _accentColor = Color(0xFFC5A97B);

const String _biskvitImage = 'assets/biskvit.png';

String _norm(String s) => s.trim().toLowerCase();

// Biskvitning bitta bo'limi.
class _BiskvitSection {
  final String title;
  final String subtitle;
  final IconData icon;
  // Backend kategoriya nomining mumkin bo'lgan variantlari (kichik harfda),
  // USTUNLIK tartibida: birinchi topilgani olinadi. Oxirgilari — avvalgi
  // versiya avtomatik yaratgan nomlar.
  final List<String> aliases;
  // Hech biri topilmasa shu nom bilan yaratiladi.
  final String createName;

  const _BiskvitSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.aliases,
    required this.createName,
  });
}

const List<_BiskvitSection> _biskvitSections = [
  _BiskvitSection(
    title: 'Biskvit',
    subtitle: 'Biskvit shakllari',
    icon: Icons.interests_outlined,
    aliases: ['бисквит', 'бисквиты', 'biskvit', 'biskvitlar',
        'biskvit shakllari'],
    createName: 'Бисквит',
  ),
  _BiskvitSection(
    title: 'Nachinka',
    subtitle: 'Qatlamlar orasiga',
    icon: Icons.layers_outlined,
    aliases: ['начинка', 'начинки', 'nachinka', 'nachinkalar',
        'biskvit nachinkasi'],
    createName: 'Начинка',
  ),
  _BiskvitSection(
    title: 'Krem',
    subtitle: 'Krem turlari',
    icon: Icons.icecream_outlined,
    aliases: ['крем', 'кремы', 'krem', 'kremlar', 'biskvit kremi'],
    createName: 'Крем',
  ),
  _BiskvitSection(
    title: 'Bezaklar',
    subtitle: 'Украшения',
    icon: Icons.auto_awesome_outlined,
    aliases: ['украшения', 'украшение', 'ukrasheniya', 'ukrasheniye',
        'bezak', 'bezaklar', 'biskvit bezaklari'],
    createName: 'Украшения',
  ),
];

final Set<String> _allAliases = {
  for (final s in _biskvitSections) ...s.aliases,
};

// Kategoriya Biskvit bo'limiga tegishlimi — «Тех карта» ro'yxati shu bilan
// ularni yashiradi.
bool isBiskvitCategoryName(String name) => _allAliases.contains(_norm(name));

// Bo'lim kategoriyasi (aliases tartibida birinchi topilgani) yoki null.
CategoryProductAdmin? _resolve(
  _BiskvitSection s,
  Map<String, CategoryProductAdmin> byName,
) {
  for (final a in s.aliases) {
    final c = byName[a];
    if (c != null) return c;
  }
  return null;
}

Map<String, CategoryProductAdmin> _indexByName(
    List<CategoryProductAdmin> cats) {
  final map = <String, CategoryProductAdmin>{};
  for (final c in cats) {
    map.putIfAbsent(_norm(c.name), () => c);
  }
  return map;
}

// «Biskvit» — to'rt bo'lim.
class BiskvitPage extends StatefulWidget {
  const BiskvitPage({super.key});

  @override
  State<BiskvitPage> createState() => _BiskvitPageState();
}

class _BiskvitPageState extends State<BiskvitPage> {
  // Kategoriya yaratilayotganda ikkinchi bosish dublikat ochmasin.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CategoryProviderAdmin>().getCategories();
      // Kartalardagi «N ta» soni uchun (allaqachon yuklangan bo'lsa — jim).
      context.read<ProductProviderAdmin>().initializeProducts();
    });
  }

  // Bo'lim kategoriyasi — bor bo'lsa o'sha, yo'q bo'lsa backend'da yaratiladi.
  Future<CategoryProductAdmin?> _ensureCategory(_BiskvitSection s) async {
    final cats = context.read<CategoryProviderAdmin>();
    if (cats.categories.isEmpty) await cats.getCategories();
    if (!mounted) return null;
    final existing = _resolve(s, _indexByName(cats.categories));
    if (existing != null) return existing;

    final upload = context.read<CategoryProviderAdminUpload>();
    final ok = await upload.createCategory(
      CategoryProductAdmin(
          id: 0, name: s.createName, imageUrl: null, printerId: 1),
    );
    if (!mounted) return null;
    if (!ok) {
      _snack(upload.error ?? '«${s.createName}» kategoriyasi yaratilmadi');
      return null;
    }
    await cats.getCategories();
    if (!mounted) return null;
    return _resolve(s, _indexByName(cats.categories));
  }

  Future<void> _openSection(_BiskvitSection s) async {
    if (_busy) return;
    setState(() => _busy = true);
    final category = await _ensureCategory(s);
    if (!mounted) return;
    setState(() => _busy = false);
    if (category == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShefTechCardProductsPage(
          categoryId: category.id,
          categoryName: 'Biskvit — ${s.title}',
          canAddProducts: true,
        ),
      ),
    );
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: const Text(
          'Biskvit',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: _accentColor,
                ),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          // Tepada guruh rasmi — qaysi bo'limda turganini ko'rsatib turadi.
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 150,
              color: Colors.white,
              alignment: Alignment.center,
              child: Image.asset(
                _biskvitImage,
                height: 130,
                cacheHeight: 390,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Sahifada atigi 4 karta — ikkala provider'ni kuzatish arzon.
          Consumer2<CategoryProviderAdmin, ProductProviderAdmin>(
            builder: (context, cats, products, _) {
              final byName = _indexByName(cats.categories);
              final counts = <int, int>{};
              for (final p in products.products) {
                counts[p.categoryId] = (counts[p.categoryId] ?? 0) + 1;
              }
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.05,
                children: [
                  for (final s in _biskvitSections)
                    _SectionCard(
                      section: s,
                      count: counts[_resolve(s, byName)?.id] ?? 0,
                      onTap: () => _openSection(s),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// Biskvit bo'limi kartasi (shef bosh menyusidagi _MenuCard uslubida).
class _SectionCard extends StatelessWidget {
  final _BiskvitSection section;
  final int count;
  final VoidCallback onTap;

  const _SectionCard({
    required this.section,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(section.icon, color: _accentColor, size: 26),
                  ),
                  const Spacer(),
                  if (count > 0)
                    Text(
                      '$count ta',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                section.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                section.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
