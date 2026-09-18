// shef/ui/biskvit_page.dart — shef bosh menyusidagi «Biskvit» bo'limi
// (BiskvitPage): tepada biskvit rasmi (assets/biskvit.png), ostida to'rt
// bo'lim — Shakllar / Nachinka / Krem / Bezaklar. Har bo'lim backend'dagi ODDIY kategoriya (nomi _BiskvitSection.
// categoryName): birinchi ochilganda yo'q bo'lsa avtomatik yaratiladi, so'ng
// PfStockPage shu kategoriyaga qulflangan holda ochiladi. Backend'da
// kategoriya ierarxiyasi yo'q — «Biskvit» guruhi faqat shu ekranda.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/category_model.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/upload_image_provider.dart';
import 'package:uz_ai_dev/shef/model/production_model.dart';
import 'package:uz_ai_dev/shef/provider/shef_provider.dart';
import 'package:uz_ai_dev/shef/ui/pf_stock_page.dart';

const Color _bgColor = Color(0xFFFAF6F1);
const Color _accentColor = Color(0xFFC5A97B);

const String _biskvitImage = 'assets/biskvit.png';

// Biskvitning bitta bo'limi: ekrandagi nomi, backend kategoriya nomi, ikonka.
class _BiskvitSection {
  final String title;
  final String categoryName;
  final String subtitle;
  final IconData icon;

  const _BiskvitSection(this.title, this.categoryName, this.subtitle, this.icon);
}

const List<_BiskvitSection> _biskvitSections = [
  _BiskvitSection('Shakllar', 'Biskvit shakllari', 'Biskvit shakllari',
      Icons.interests_outlined),
  _BiskvitSection('Nachinka', 'Biskvit nachinkasi', 'Qatlamlar orasiga',
      Icons.layers_outlined),
  _BiskvitSection('Krem', 'Biskvit kremi', 'Krem turlari',
      Icons.icecream_outlined),
  _BiskvitSection('Bezaklar', 'Biskvit bezaklari', 'Tort bezaklari',
      Icons.auto_awesome_outlined),
];

String _norm(String s) => s.trim().toLowerCase();

// Berilgan kategoriyalar (normallashgan nom) ichidagi пф soni.
int _countIn(List<PfStockRow> rows, Set<String> categoryNames) {
  var n = 0;
  for (final r in rows) {
    if (categoryNames.contains(_norm(r.categoryName))) n++;
  }
  return n;
}

// «Biskvit» — to'rt bo'lim.
class BiskvitPage extends StatefulWidget {
  const BiskvitPage({super.key});

  @override
  State<BiskvitPage> createState() => _BiskvitPageState();
}

class _BiskvitPageState extends State<BiskvitPage> {
  // Kategoriya yaratilayotganda ikkinchi bosish yangi dublikat ochmasin.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CategoryProviderAdmin>().getCategories();
      // Kartalardagi «N ta» soni uchun.
      context.read<ShefProvider>().fetchPfStock();
    });
  }

  CategoryProductAdmin? _findCategory(String name) {
    final key = _norm(name);
    for (final c in context.read<CategoryProviderAdmin>().categories) {
      if (_norm(c.name) == key) return c;
    }
    return null;
  }

  // Bo'lim kategoriyasi — bor bo'lsa o'sha, yo'q bo'lsa backend'da yaratiladi.
  Future<int?> _ensureCategory(String name) async {
    final cats = context.read<CategoryProviderAdmin>();
    if (cats.categories.isEmpty) await cats.getCategories();
    if (!mounted) return null;
    final existing = _findCategory(name);
    if (existing != null) return existing.id;

    final upload = context.read<CategoryProviderAdminUpload>();
    final ok = await upload.createCategory(
      CategoryProductAdmin(id: 0, name: name, imageUrl: null, printerId: 1),
    );
    if (!mounted) return null;
    if (!ok) {
      _snack(upload.error ?? '«$name» kategoriyasi yaratilmadi');
      return null;
    }
    await cats.getCategories();
    if (!mounted) return null;
    return _findCategory(name)?.id;
  }

  Future<void> _openSection(_BiskvitSection s) async {
    if (_busy) return;
    setState(() => _busy = true);
    final id = await _ensureCategory(s.categoryName);
    if (!mounted) return;
    setState(() => _busy = false);
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PfStockPage(
          lockedCategoryId: id,
          title: 'Biskvit — ${s.title}',
        ),
      ),
    );
    // Qaytganda kartadagi sonlar yangilansin (пф qo'shilgan bo'lishi mumkin).
    if (!mounted) return;
    context.read<ShefProvider>().fetchPfStock();
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
          Selector<ShefProvider, List<PfStockRow>>(
            selector: (_, p) => p.pfStock,
            builder: (context, rows, _) => GridView.count(
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
                    count: _countIn(rows, {_norm(s.categoryName)}),
                    onTap: () => _openSection(s),
                  ),
              ],
            ),
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
