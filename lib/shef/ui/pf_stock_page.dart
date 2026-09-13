// shef/ui/pf_stock_page.dart — «Полуфабрикат qoldig'i» ekrani: PfStockPage —
// shef skladidagi pf'lar ro'yxati KATEGORIYA bo'yicha guruhlangan holda
// (category_group.dart; Bor / Band / Mumkin ustunlari, qidiruv, kategoriya
// tab-bar filtri, tugaganlari qizil bilan). GET /api/production/pf-stock,
// ShefProvider ustida.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:uz_ai_dev/shef/model/production_model.dart';
import 'package:uz_ai_dev/shef/provider/shef_provider.dart';
import 'package:uz_ai_dev/shef/ui/widgets/category_group.dart';

// Shef uchun полуфабрикат qoldig'i: qaysi pf bor, nechtadan bor, nechtasi
// band (boshqa buyurtmalarga), nechtasini ishlatish mumkin.
// Buyurtmaga bog'liq emas — umumiy sklad ko'rinishi.
// Ro'yxat kategoriya sarlavhalari ostida guruhlanadi (bitta kategoriya bo'lsa
// sarlavha chiqmaydi). Qidiruv ostida kategoriya TAB-BAR'i bor: «Hammasi» +
// har bir kategoriya (soni bilan); tanlangan tab ro'yxatni shu kategoriyaga
// qisadi (u holda guruh sarlavhasi ham chiqmaydi — bitta guruh). Guruhlash har
// build'da emas — faqat qoldiq ro'yxati, qidiruv yoki tanlangan kategoriya
// o'zgarganda hisoblanib keshlanadi (`_rebuildGroups`), ListView esa yassi
// (flat) indeks ustida chizadi.
class PfStockPage extends StatefulWidget {
  const PfStockPage({super.key});

  @override
  State<PfStockPage> createState() => _PfStockPageState();
}

class _PfStockPageState extends State<PfStockPage> {
  static const Color _bgColor = Color(0xFFFAF6F1);
  static const Color _accentColor = Color(0xFFC5A97B);

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Tanlangan kategoriya tabi: `_kAllKey` — hammasi, aks holda `_CategoryTab.key`.
  static const String _kAllKey = '*';
  String _selectedCatKey = _kAllKey;

  // ── Guruhlash keshi ──────────────────────────────────────────────────────
  // Manba ro'yxat (identity), qidiruv matni va tanlangan kategoriya
  // o'zgarmaguncha qayta hisoblamaymiz.
  List<PfStockRow>? _groupsSource;
  String _groupsQuery = '';
  String _groupsCatKey = _kAllKey;
  // Yassi (flat) ro'yxat: CategoryHeader | PfStockRow elementlari.
  List<Object> _entries = const [];
  // Filtrdan keyingi qatorlar soni (bo'shligini tekshirish uchun).
  int _rowCount = 0;
  // Tanlangan kategoriya doirasidagi (qidiruvdan mustaqil) qatorlar soni va
  // ulardan qoldig'i tugaganlari — xulosa qatori uchun.
  int _scopeCount = 0;
  int _emptyCount = 0;
  // Tab-bar uchun kategoriyalar (manba ro'yxatdan; alifbo tartibida,
  // «Kategoriyasiz» oxirida). Faqat manba o'zgarganda qayta hisoblanadi.
  List<_CategoryTab> _catTabs = const [];
  // Tab-bar'ni qayta yaratish kaliti (kategoriyalar to'plami o'zgarsa).
  String _catTabsKey = '';

  // Faqat manba/qidiruv/kategoriya o'zgarganda ishlaydi (build ichidan
  // chaqiriladi, lekin setState qilmaydi — bu shunchaki kesh).
  void _rebuildGroups(List<PfStockRow> source, String query) {
    if (identical(_groupsSource, source) &&
        _groupsQuery == query &&
        _groupsCatKey == _selectedCatKey) {
      return;
    }
    // Manba yangilansa tab'lar ham qayta hisoblanadi (tanlangan kategoriya
    // yo'qolgan bo'lsa `_selectedCatKey` «hammasi»ga qaytadi — shuning uchun
    // kalit shundan KEYIN o'qiladi).
    if (!identical(_groupsSource, source)) _rebuildCatTabs(source);
    final catKey = _selectedCatKey;
    _groupsSource = source;
    _groupsQuery = query;
    _groupsCatKey = catKey;

    // Avval kategoriya doirasi (xulosa shu doirada), keyin qidiruv.
    final scoped = catKey == _kAllKey
        ? source
        : source.where((r) => _catKeyOf(r) == catKey).toList();
    _scopeCount = scoped.length;
    _emptyCount = scoped.where((r) => r.isEmptyStock).length;

    final rows = query.isEmpty
        ? scoped
        : scoped.where((r) => r.name.toLowerCase().contains(query)).toList();
    _rowCount = rows.length;
    _entries = buildCategoryEntries<PfStockRow>(
      rows,
      categoryId: (r) => r.categoryId,
      categoryName: (r) => r.categoryName,
    );
  }

  // Kategoriya kaliti — category_group.dart bilan bir xil qoida: nomi bo'sh
  // bo'lsa hammasi bitta «Kategoriyasiz» guruhi (''), aks holda id|nom.
  static String _catKeyOf(PfStockRow r) {
    final name = r.categoryName.trim();
    return name.isEmpty ? '' : '${r.categoryId}|$name';
  }

  // Manba ro'yxatdan tab'lar ro'yxati (soni bilan). 2 tadan kam kategoriya
  // bo'lsa tab-bar umuman chiqmaydi (bo'sh ro'yxat).
  void _rebuildCatTabs(List<PfStockRow> source) {
    final counts = <String, int>{};
    final titles = <String, String>{};
    for (final r in source) {
      final key = _catKeyOf(r);
      counts[key] = (counts[key] ?? 0) + 1;
      titles[key] = key.isEmpty ? kUncategorizedTitle : r.categoryName.trim();
    }
    if (counts.length < 2) {
      _catTabs = const [];
      _catTabsKey = '';
      _selectedCatKey = _kAllKey;
      return;
    }
    final keys = counts.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty) return b.isEmpty ? 0 : 1;
        if (b.isEmpty) return -1;
        final c = titles[a]!.toLowerCase().compareTo(titles[b]!.toLowerCase());
        return c != 0 ? c : a.compareTo(b);
      });
    _catTabs = [
      _CategoryTab(_kAllKey, 'Hammasi', source.length),
      for (final k in keys) _CategoryTab(k, titles[k]!, counts[k]!),
    ];
    _catTabsKey = keys.join(',');
    // Tanlangan kategoriya yo'qolgan bo'lsa (yangilangan ro'yxat) — hammasi.
    if (!counts.containsKey(_selectedCatKey) && _selectedCatKey != _kAllKey) {
      _selectedCatKey = _kAllKey;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ShefProvider>().fetchPfStock();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: const Text(
          'Полуфабрикат qoldig\'i',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          // Jami soni — ro'yxat yuklanganda ko'rinadi (qidiruvdan mustaqil).
          Selector<ShefProvider, int>(
            selector: (_, p) => p.pfStock.length,
            builder: (context, total, _) => total == 0
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Center(
                      child: Text(
                        '$total ta',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: Consumer<ShefProvider>(
        builder: (context, provider, child) {
          if (provider.isLoadingPfStock && provider.pfStock.isEmpty) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          if (provider.pfStockError != null && provider.pfStock.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      provider.pfStockError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => provider.fetchPfStock(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Qayta urinish'),
                    ),
                  ],
                ),
              ),
            );
          }

          final all = provider.pfStock;
          final query = _searchQuery.trim().toLowerCase();
          // Kategoriya guruhlari keshdan (faqat ro'yxat/qidiruv/tab o'zgarsa).
          _rebuildGroups(all, query);
          final entries = _entries;

          return Column(
            children: [
              if (all.isNotEmpty) ...[
                _searchField(),
                if (_catTabs.isNotEmpty) _categoryTabBar(),
                _summaryLine(_scopeCount, _emptyCount),
                _columnsHeader(),
              ],
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => provider.fetchPfStock(),
                  child: _rowCount == 0
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 140),
                            Center(
                              child: Text(
                                all.isEmpty
                                    ? 'Полуфабрикат yo\'q'
                                    : 'Topilmadi',
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            // Yassi ro'yxat: sarlavha yoki пф qatori.
                            if (entry is CategoryHeader) {
                              return CategoryHeaderTile(header: entry);
                            }
                            return _PfStockTile(row: entry as PfStockRow);
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Полуфабрикат qidirish...',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.clear, color: Colors.grey),
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // Kategoriya tab-bar'i: «Hammasi» + har bir kategoriya (soni bilan).
  // TabBarView yo'q — tab bosilganda faqat ro'yxat filtri o'zgaradi.
  // DefaultTabController kaliti kategoriyalar to'plamiga bog'langan: to'plam
  // o'zgarsa controller qayta yaratilib, tanlangan tab'ga tushadi.
  Widget _categoryTabBar() {
    final tabs = _catTabs;
    var initial = tabs.indexWhere((t) => t.key == _selectedCatKey);
    if (initial < 0) initial = 0;
    return DefaultTabController(
      key: ValueKey('pf-cat-tabs:$_catTabsKey'),
      length: tabs.length,
      initialIndex: initial,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          indicatorColor: _accentColor,
          indicatorWeight: 2.5,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.grey.shade300,
          labelColor: Colors.brown.shade800,
          unselectedLabelColor: Colors.black54,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          unselectedLabelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          onTap: (i) {
            final key = tabs[i].key;
            if (key == _selectedCatKey) return;
            setState(() => _selectedCatKey = key);
          },
          tabs: [
            for (final t in tabs)
              Tab(
                height: 38,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.title),
                    const SizedBox(width: 5),
                    Text(
                      '${t.count}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Qisqa xulosa: «12 ta полуфабрикат • 3 tasi tugagan» (tanlangan kategoriya
  // doirasida, qidiruvdan mustaqil).
  Widget _summaryLine(int total, int emptyCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
      child: Row(
        children: [
          Text(
            '$total ta полуфабрикат',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          if (emptyCount > 0) ...[
            Text(
              ' • ',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
            ),
            Text(
              '$emptyCount tasi tugagan',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _columnsHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(22, 0, 22, 4),
      child: Row(
        children: [
          Expanded(child: SizedBox()),
          SizedBox(
            width: _PfStockTile.colWidth,
            child: Text('Bor',
                textAlign: TextAlign.right, style: _PfStockTile.headStyle),
          ),
          SizedBox(
            width: _PfStockTile.colWidth,
            child: Text('Band',
                textAlign: TextAlign.right, style: _PfStockTile.headStyle),
          ),
          SizedBox(
            width: _PfStockTile.colWidthWide,
            child: Text('Mumkin',
                textAlign: TextAlign.right, style: _PfStockTile.headStyle),
          ),
        ],
      ),
    );
  }
}

// Tab-bar'dagi bitta kategoriya: kalit (`_kAllKey` yoki id|nom yoki '' —
// Kategoriyasiz), ko'rsatiladigan nomi va manba ro'yxatdagi soni.
class _CategoryTab {
  final String key;
  final String title;
  final int count;

  const _CategoryTab(this.key, this.title, this.count);
}

// Ro'yxatdagi bitta полуфабрикат qatori: rasm + nomi (+ partiya/ishlatilish)
// va o'ngda Bor / Band / Mumkin ustunlari.
class _PfStockTile extends StatelessWidget {
  final PfStockRow row;

  const _PfStockTile({required this.row});

  static const Color _accentColor = Color(0xFFC5A97B);
  static const double colWidth = 48;
  static const double colWidthWide = 58;
  static const TextStyle headStyle =
      TextStyle(fontSize: 11, color: Colors.grey);

  // Sonni chiroyli ko'rsatish: butun bo'lsa kasrsiz, aks holda 1 xona.
  static String _fmtNum(num v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  static String _fullImageUrl(String url) {
    if (url.isEmpty) return '';
    return url.startsWith('http') ? url : '${AppUrls.baseUrl}$url';
  }

  // «1 partiya = 20 dona • 3 ta mahsulotda ishlatiladi» (bo'sh bo'laklarsiz).
  String get _subtitle {
    final parts = <String>[
      if (row.batchQty > 0) '1 partiya = ${row.batchQty} dona',
      if (row.usedIn > 0) '${row.usedIn} ta mahsulotda ishlatiladi',
    ];
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final out = row.isEmptyStock;
    final imageUrl = _fullImageUrl(row.imageUrl);
    final subtitle = _subtitle;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: out ? Colors.red.shade200 : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 52,
                height: 52,
                child: imageUrl.isEmpty
                    ? Container(
                        color: Colors.grey.shade200,
                        child: Icon(Icons.cake_outlined,
                            color: Colors.grey.shade400),
                      )
                    : AppNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_) =>
                            Container(color: Colors.grey.shade200),
                        errorWidget: (_) => Container(
                          color: Colors.grey.shade200,
                          child: Icon(Icons.broken_image,
                              color: Colors.grey.shade400),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (out) ...[
                        Icon(Icons.warning_amber_rounded,
                            size: 16, color: Colors.red.shade700),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          row.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (row.unit.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          row.unit,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _numCell(_fmtNum(row.stock), Colors.black87, FontWeight.w600),
            _numCell(
              _fmtNum(row.reserved),
              row.reserved > 0 ? Colors.orange.shade800 : Colors.grey.shade500,
              FontWeight.w500,
            ),
            _numCell(
              _fmtNum(row.availableClamped),
              out ? Colors.red.shade700 : _accentColor,
              FontWeight.bold,
              width: colWidthWide,
            ),
          ],
        ),
      ),
    );
  }

  Widget _numCell(String text, Color color, FontWeight weight,
      {double width = colWidth}) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 14.5, color: color, fontWeight: weight),
      ),
    );
  }
}
