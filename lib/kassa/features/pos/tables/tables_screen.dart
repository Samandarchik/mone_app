import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/app_state.dart';
import '../../../core/services/local_db.dart';
import '../../../core/services/ui_prefs.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../order/order_screen.dart';
import '../../../core/widgets/tutorial_widgets.dart';

class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});
  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  List<Map<String, dynamic>> _zones = [];
  Map<int, List<Map<String, dynamic>>> _tablesByZone = {};
  bool _loading = true;

  /// Zonalar yuklanmadi — bo'sh ekran o'rniga sabab ko'rsatamiz.
  bool _loadError = false;
  int _selectedZone = 0;
  final _zonePageController = PageController();

  @override
  void initState() {
    super.initState();
    _load();
    AppState().addListener(_onStateChanged);
  }

  @override
  void dispose() {
    AppState().removeListener(_onStateChanged);
    _zonePageController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load({bool resynced = false}) async {
    // `try/catch` SHART: `LocalDB` xatosi (qulflangan baza, migratsiya)
    // ilgari `initState` dagi kutilmagan future'dan chiqib ketardi va
    // ekran abadiy aylanuvchi belgida qolardi.
    try {
      final zones = await LocalDB().getZones();
      final tbls = <int, List<Map<String, dynamic>>>{};
      for (final z in zones) {
        final zid = z['id'] as int? ?? 0;
        final tables = await LocalDB().getTables(zoneId: zid);
        tbls[zid] = tables;
      }

      if (zones.isEmpty) {
        // CHEKSIZ REKURSIYA edi.
        //
        // `forceSync` o'z xatosini yutadi, shuning uchun server o'chiq
        // bo'lsa zonalar hech qachon to'lmasdi va `_load()` o'zini
        // cheksiz chaqirardi: har safar 10 soniyalik `/api/zones`
        // so'rovi bilan, ilova yopilgunicha, hatto `dispose` dan keyin
        // ham. Endi bir marta urinamiz va xato ekranini ko'rsatamiz.
        if (!resynced) {
          await AppState().forceSync();
          if (!mounted) return;
          return _load(resynced: true);
        }
        if (mounted) {
          setState(() {
            _zones = [];
            _tablesByZone = {};
            _loading = false;
            _loadError = true;
          });
        }
        return;
      }

      if (!resynced) {
        final stale = tbls.values.any(
          (list) => list.where((t) => (t['number'] ?? 0) == 0).length > 1,
        );
        if (stale) {
          await AppState().forceSync();
          if (!mounted) return;
          return _load(resynced: true);
        }
      }

      if (mounted) {
        setState(() {
          _zones = zones;
          _tablesByZone = tbls;
          _loading = false;
          _loadError = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = true;
        });
      }
    }
  }

  // ---- stats over the currently visible zone ----
  ({int free, int busy}) _zoneStats(int zoneIndex) {
    if (zoneIndex >= _zones.length) return (free: 0, busy: 0);
    final zone = _zones[zoneIndex];
    final zid = zone['id'] as int? ?? 0;
    final tables = _tablesByZone[zid] ?? [];
    int free = 0, busy = 0;
    for (final t in tables) {
      final sku = t['sku'] ?? '';
      if (AppState().getTableStatus(sku) == 'free') {
        free++;
      } else {
        busy++;
      }
    }
    return (free: free, busy: busy);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // Yuklash yiqilganini AYTAMIZ. Ilgari ekran shunchaki bo'sh qolardi va
    // kassir stollar yo'q deb o'ylardi.
    if (_loadError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 40,
                color: AppColors.danger,
              ),
              const SizedBox(height: 10),
              const Text(
                'Stollar yuklanmadi — server bilan aloqa yo‘q',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _loadError = false;
                  });
                  _load();
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Qayta urinish'),
              ),
            ],
          ),
        ),
      );
    }

    final shiftOpen = AppState().shift?['status'] == 'open';
    if (!shiftOpen) {
      return EmptyState(
        icon: Icons.lock_rounded,
        title: 'Smena ochilmagan',
        subtitle: 'Buyurtma qabul qilish uchun smenani oching',
        color: AppColors.warning,
        action: FilledButton.icon(
          onPressed: _openShift,
          icon: const Icon(Icons.lock_open_rounded, size: 18),
          label: const Text('Smenani ochish'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          ),
        ),
      );
    }

    if (_zones.isEmpty) {
      return const EmptyState(
        icon: Icons.layers_rounded,
        title: 'Zonalar yo\'q',
        subtitle: 'Admin paneldan zona qo\'shing',
      );
    }

    // Zonalardan keyingi uchta maxsus sahifa: Saboy, Dostafka, Yandex.
    // Yandex ALOHIDA turadi: uning cheklari ham `type='delivery'`, lekin
    // ularni kassir yaratmaydi va boshqacha yuritiladi (pul Yandexda,
    // kuryerni ham Yandex yuboradi) — Dostafka bilan aralashib ketmasin.
    final totalPages = _zones.length + 3;
    final tabNames = [
      ..._zones.map(
        (z) => z['name'] is Map ? z['name']['uz'] : z['name'] ?? '',
      ),
      'Saboy',
      'Dostafka',
      'Yandex',
    ];

    final isZonePage = _selectedZone < _zones.length;
    final stats = isZonePage ? _zoneStats(_selectedZone) : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = AppBreakpoints.isPhone(constraints.maxWidth);
        final hPad = compact ? 14.0 : 24.0;

        return Column(
          children: [
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, compact ? 10 : 16, hPad, 6),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'Stollar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 19 : 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const _LiveBadge(),
                  const SizedBox(width: 8),
                  const TutorialHelpButton('pos.tables', size: 26),
                  const Spacer(),
                  if (stats != null) ...[
                    _MiniStat(
                      label: 'bo\'sh',
                      value: stats.free,
                      color: AppColors.success,
                      big: !compact,
                    ),
                    const SizedBox(width: 6),
                    _MiniStat(
                      label: 'band',
                      value: stats.busy,
                      color: AppColors.danger,
                      big: !compact,
                    ),
                  ],
                ],
              ),
            ),
            // Zone tabs
            SizedBox(
              height: compact ? 52 : 60,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: hPad),
                itemCount: totalPages,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) {
                  final isSaboy = i == _zones.length;
                  final isDostafka = i == _zones.length + 1;
                  final isYandex = i == _zones.length + 2;
                  final selected = _selectedZone == i;
                  IconData? icon;
                  Color accent = AppColors.primary;
                  if (isSaboy) {
                    icon = Icons.takeout_dining_rounded;
                    accent = AppColors.warning;
                  } else if (isDostafka) {
                    icon = Icons.delivery_dining_rounded;
                    accent = AppColors.success;
                  } else if (isYandex) {
                    icon = Icons.fastfood_rounded;
                    accent = kYandexColor;
                  }
                  return Center(
                    child: KChip(
                      label: tabNames[i],
                      icon: icon,
                      accent: accent,
                      selected: selected,
                      big: !compact,
                      onTap: () {
                        setState(() => _selectedZone = i);
                        _zonePageController.animateToPage(
                          i,
                          duration: AppDuration.slow,
                          curve: Curves.easeInOut,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: PageView.builder(
                controller: _zonePageController,
                itemCount: totalPages,
                onPageChanged: (i) => setState(() => _selectedZone = i),
                itemBuilder: (ctx, i) {
                  if (i == _zones.length) {
                    return _buildSaboyDostafkaPage(
                      'takeaway',
                      'Saboy',
                      AppColors.warning,
                      Icons.takeout_dining_rounded,
                      compact,
                    );
                  }
                  if (i == _zones.length + 1) {
                    return _buildSaboyDostafkaPage(
                      'delivery',
                      'Dostafka',
                      AppColors.success,
                      Icons.delivery_dining_rounded,
                      compact,
                    );
                  }
                  if (i == _zones.length + 2) {
                    return _buildYandexPage(compact);
                  }
                  return _buildTableGridForZone(i, compact);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSaboyDostafkaPage(
    String type,
    String label,
    Color color,
    IconData icon,
    bool compact,
  ) {
    // Yandex cheklari ham `type='delivery'` — lekin ular o'z sahifasida
    // ko'rinadi, shuning uchun bu yerdan chiqarib tashlanadi. Aks holda
    // bitta chek ikkita tabda turardi.
    final activeOrders = AppState().activeOrders
        .where(
          (o) =>
              o['type'] == type &&
              o['source'] != 'yandex' &&
              o['status'] != 'completed' &&
              o['status'] != 'cancelled',
        )
        .toList();

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 16,
            8,
            compact ? 14 : 16,
            10,
          ),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: () => _createOrder(type),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(
                'Yangi $label buyurtma',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: activeOrders.isEmpty
              ? EmptyState(
                  icon: icon,
                  title: '$label buyurtma yo\'q',
                  subtitle: 'Yangi buyurtma yarating',
                  color: color,
                )
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 14 : 16,
                    0,
                    compact ? 14 : 16,
                    16,
                  ),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    // Kenglikka qarab ustun soni o'zi hisoblanadi
                    maxCrossAxisExtent: compact ? 160 : 180,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: compact ? 112 : 124,
                  ),
                  itemCount: activeOrders.length,
                  itemBuilder: (ctx, i) {
                    final o = activeOrders[i];
                    final orderNum = o['order_number'] ?? '';
                    final total = o['total'] as int? ?? 0;
                    final status = o['status'] ?? 'new';
                    return _OrderCard(
                      number: orderNum.toString().split('-').last,
                      total: total,
                      status: status,
                      accent: color,
                      icon: icon,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderTabsScreen(
                              tableSKU: null,
                              tableLabel: '$label #$orderNum',
                              order: o,
                              orderType: type,
                            ),
                          ),
                        ).then((_) => setState(() {}));
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Yandex Eda sahifasi.
  ///
  /// Saboy/Dostafka'dan farqi: bu yerda «Yangi buyurtma» TUGMASI YO'Q —
  /// Yandex zakazini kassir yaratmaydi, u Yandexdan o'zi tushadi. Kassirning
  /// ishi: kelgan chekni ochib statusini yuritish (Tayyorlanmoqda → Tayyor).
  /// Pul ham Yandexda to'langan, shuning uchun chek yopishda pul olinmaydi.
  Widget _buildYandexPage(bool compact) {
    final orders = AppState().activeOrders
        .where(
          (o) =>
              o['source'] == 'yandex' &&
              o['status'] != 'completed' &&
              o['status'] != 'cancelled',
        )
        .toList();

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 16,
            8,
            compact ? 14 : 16,
            10,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: kYandexColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: kYandexColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.fastfood_rounded,
                  size: 20,
                  color: kYandexColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    orders.isEmpty
                        ? 'Yandexdan kelgan buyurtmalar shu yerda ko\'rinadi'
                        : '${orders.length} ta faol Yandex buyurtmasi — '
                              'pul Yandexda to\'langan',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kYandexColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: orders.isEmpty
              ? const EmptyState(
                  icon: Icons.fastfood_rounded,
                  title: 'Yandex buyurtma yo\'q',
                  subtitle: 'Buyurtma kelganda o\'zi paydo bo\'ladi',
                  color: kYandexColor,
                )
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 14 : 16,
                    0,
                    compact ? 14 : 16,
                    16,
                  ),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: compact ? 160 : 180,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: compact ? 112 : 124,
                  ),
                  itemCount: orders.length,
                  itemBuilder: (ctx, i) {
                    final o = orders[i];
                    final orderNum = (o['order_number'] ?? '').toString();
                    return _OrderCard(
                      number: orderNum.split('-').last,
                      total: o['total'] as int? ?? 0,
                      status: (o['status'] ?? 'new').toString(),
                      accent: kYandexColor,
                      icon: Icons.fastfood_rounded,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderTabsScreen(
                              tableSKU: null,
                              tableLabel: 'Yandex #$orderNum',
                              order: o,
                              orderType: 'delivery',
                            ),
                          ),
                        ).then((_) => setState(() {}));
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTableGridForZone(int zoneIndex, bool compact) {
    if (zoneIndex >= _zones.length) return const SizedBox();
    final zone = _zones[zoneIndex];
    final zoneId = zone['id'] as int? ?? 0;
    final tables = _tablesByZone[zoneId] ?? [];
    final zoneName =
        (zone['name'] is Map ? zone['name']['uz'] : zone['name'] ?? '')
            .toString();
    final pad = compact ? 14.0 : 24.0;

    return RefreshIndicator(
      onRefresh: () async {
        await AppState().forceSync();
        await _load();
      },
      child: ValueListenableBuilder<double>(
        valueListenable: UiPrefs().tableScale,
        builder: (ctx, scale, _) => LayoutBuilder(
          builder: (ctx, c) {
            // Stol katagi ekranga moslashadi.
            //
            // ILGARI: planshetda ham 152pt li katak edi — 13 dyuymli iPad'da
            // 6 ustun chiqib, ekranning uchdan ikkisi bo'sh qolardi va stol
            // raqamlari uzoqdan ko'rinmasdi. Endi kataklar ekranga qarab
            // kattalashadi, lekin bir qatorda 8 tadan oshmaydi.
            //
            // `scale` — kassir sozlamadan tanlagan masshtab (UiPrefs):
            // 1.0 da xatti-harakat avvalgidek qoladi, kichraytirilganda
            // ustun chegarasi kengayadi, kattalashtirilganda torayadi.
            final gap = compact ? 10.0 : 14.0;
            final avail = c.maxWidth - pad * 2;
            final target = (compact ? 118.0 : 168.0) * scale;
            final minCols = scale > 1.01 ? 2 : (compact ? 3 : 4);
            final maxCols = scale < 0.99 ? 12 : 8;
            final cols = ((avail + gap) / (target + gap)).round().clamp(
              minCols,
              maxCols,
            );
            final tileW = (avail - gap * (cols - 1)) / cols;
            final tileH = (tileW * 0.86).clamp(100.0 * scale, 170.0 * scale);

            return GridView.builder(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 20),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: gap,
                crossAxisSpacing: gap,
                mainAxisExtent: tileH,
              ),
              itemCount: tables.length,
              itemBuilder: (ctx, i) {
                final t = tables[i];
                final sku = t['sku'] ?? '';
                final status = AppState().getTableStatus(sku);
                final orderNum = AppState().getTableOrderNumber(sku);
                final isFree = status == 'free';
                final fullLabel = (t['label'] ?? sku).toString();

                return _TableCard(
                  label: _tileLabel(t, zoneName),
                  fullLabel: fullLabel,
                  free: isFree,
                  orderNumber: orderNum,
                  onTap: () => _openTable(t, sku),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Zona nomi tabda turgani uchun kartada faqat stol raqami ko'rsatiladi:
  /// «ZAL-3» → «3». Nomi boshqacha bo'lsa to'liq ko'rsatiladi.
  String _tileLabel(Map<String, dynamic> t, String zoneName) {
    final label = (t['label'] ?? '').toString().trim();
    if (label.isNotEmpty && zoneName.isNotEmpty) {
      final prefix = '$zoneName-'.toLowerCase();
      if (label.toLowerCase().startsWith(prefix)) {
        final rest = label.substring(prefix.length).trim();
        if (rest.isNotEmpty) return rest;
      }
    }
    if (label.isNotEmpty) return label;
    final number = t['number'];
    if (number is int && number > 0) return '$number';
    return (t['sku'] ?? '').toString();
  }

  void _openTable(Map<String, dynamic> table, String sku) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderTabsScreen(
          tableSKU: sku,
          tableLabel: table['label'] ?? sku,
          order: null,
        ),
      ),
    ).then((_) => setState(() {}));
  }

  void _openShift() {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Smenani ochish'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            labelText: 'Kassadagi naqd summa',
            suffixText: 'so\'m',
          ),
          keyboardType: TextInputType.number,
          inputFormatters: const [MoneyInputFormatter()],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                // parseIntField: maydon "1 200 000" ko'rinishida formatlanadi
                await ApiService().openShift(parseIntField(c.text) ?? 0);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        friendlyError(e, fallback: 'Smena ochilmadi'),
                      ),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('Ochish'),
          ),
        ],
      ),
    );
  }

  void _createOrder(String type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderTabsScreen(
          tableSKU: null,
          tableLabel: type == 'takeaway' ? 'Saboy' : 'Dostafka',
          order: null,
          orderType: type,
        ),
      ),
    ).then((_) => setState(() {}));
  }
}

// ============================================================
// Mini stat pill (Bo'sh: 4)
// ============================================================

class _MiniStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final bool big;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: big ? 13 : 10,
        vertical: big ? 7 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: big ? 8 : 6,
            height: big ? 8 : 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$value $label',
            style: TextStyle(
              fontSize: big ? 13 : 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Table card
// ============================================================

class _TableCard extends StatelessWidget {
  final String label;
  final String fullLabel;
  final bool free;
  final String? orderNumber;
  final VoidCallback onTap;

  const _TableCard({
    required this.label,
    required this.fullLabel,
    required this.free,
    required this.orderNumber,
    required this.onTap,
  });

  /// «26-07-25-P000007» → «#P7» — katakka sig'adigan qisqa ko'rinish
  String get _shortOrder {
    final on = orderNumber;
    if (on == null || on.isEmpty) return 'Band';
    final tail = on.split('-').last;
    final m = RegExp(r'^([A-Za-z]*)0*(\d+)$').firstMatch(tail);
    if (m != null) return '#${m.group(1)}${m.group(2)}';
    return '#$tail';
  }

  @override
  Widget build(BuildContext context) {
    final color = free ? AppColors.success : AppColors.danger;
    final status = free ? 'Bo\'sh' : _shortOrder;

    return Semantics(
      button: true,
      label: '$fullLabel — $status',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          // Barcha o'lchamlar katak balandligidan olinadi — hech qachon
          // overflow bo'lmaydi (planshetda ham, telefonda ham)
          child: LayoutBuilder(
            builder: (context, c) {
              final h = c.maxHeight;
              final plate = (h * 0.46).clamp(34.0, 58.0);
              final labelSize = plate * 0.44;
              final statusSize = (h * 0.105).clamp(9.0, 13.0);

              return AnimatedContainer(
                duration: AppDuration.normal,
                decoration: BoxDecoration(
                  color: free ? AppColors.surface : AppColors.dangerTint,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: free
                        ? AppColors.border
                        : color.withValues(alpha: 0.35),
                    width: free ? 1 : 1.4,
                  ),
                ),
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Stol raqami — kartaning asosiy belgisi
                    Container(
                      width: plate,
                      height: plate,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: free
                            ? AppColors.successTint
                            : color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: labelSize,
                            height: 1,
                            letterSpacing: -0.5,
                            color: color,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: h * 0.06),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: statusSize,
                        color: color,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Order card (saboy/dostafka)
// ============================================================

class _OrderCard extends StatelessWidget {
  final String number;
  final int total;
  final String status;
  final Color accent;
  final IconData icon;
  final VoidCallback onTap;

  const _OrderCard({
    required this.number,
    required this.total,
    required this.status,
    required this.accent,
    required this.icon,
    required this.onTap,
  });

  Color get _statusColor {
    switch (status) {
      case 'new':
        return AppColors.danger;
      case 'preparing':
        return AppColors.warning;
      case 'ready':
        return AppColors.success;
      default:
        return AppColors.textMuted;
    }
  }

  String get _statusLabel {
    const m = {
      'new': 'Yangi',
      'preparing': 'Tayyorlanmoqda',
      'ready': 'Tayyor',
    };
    return m[status] ?? status;
  }

  @override
  Widget build(BuildContext context) {
    return KCard(
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      borderColor: accent.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, color: accent, size: 16),
              ),
              const Spacer(),
              Text(
                '#$number',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: accent,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            formatMoney(total, suffix: ' so\'m'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 5),
          StatusBadge(label: _statusLabel, color: _statusColor),
        ],
      ),
    );
  }
}

// ============================================================
// LIVE pill
// ============================================================

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.successSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 11, color: AppColors.success),
          SizedBox(width: 2),
          Text(
            'LIVE',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: AppColors.success,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
