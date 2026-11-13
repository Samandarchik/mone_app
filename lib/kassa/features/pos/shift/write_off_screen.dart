import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../../../core/utils/search_fold.dart';
import '../../../core/widgets/tutorial_widgets.dart';

/// Mahsulotni hisobdan chiqarish (spisaniya) ekrani.
class WriteOffScreen extends StatefulWidget {
  const WriteOffScreen({super.key});

  @override
  State<WriteOffScreen> createState() => _WriteOffScreenState();
}

class _WriteOffScreenState extends State<WriteOffScreen> {
  static const _reasons = [
    'Muddati o\'tdi',
    'Sindi-buzildi',
    'Degustatsiya',
    'Boshqa',
  ];

  List<dynamic> _products = [];
  Map<String, dynamic>? _selected;
  final TextEditingController _qtyC = TextEditingController(text: '1');
  final TextEditingController _noteC = TextEditingController();
  String? _reason;
  bool _submitting = false;

  List<dynamic> _writeOffs = [];
  bool _loadingList = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadWriteOffs();
  }

  @override
  void dispose() {
    _qtyC.dispose();
    _noteC.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final menu = await ApiService().getMenu();
      final products = menu['products'] as List<dynamic>? ?? [];
      if (!mounted) return;
      setState(() {
        _products =
            products.where((p) => p['status'] != 'inactive').toList();
      });
    } catch (_) {
      // menyu keshdan kelmasa ham ekran ishlayveradi
    }
  }

  Future<void> _loadWriteOffs() async {
    try {
      final res = await ApiService().getWriteOffs();
      if (!mounted) return;
      setState(() {
        _writeOffs = res['write_offs'] as List<dynamic>? ?? [];
        _loadingList = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingList = false);
    }
  }

  String _errMsg(Object e) {
    if (e is DioException && e.response?.data is Map) {
      final msg = (e.response!.data as Map)['message'];
      if (msg != null) return msg.toString();
    }
    return 'Xatolik yuz berdi';
  }

  String _productName(dynamic p) => menuName(p?['name']);

  int get _qty => int.tryParse(_qtyC.text.trim()) ?? 0;

  bool get _canSubmit =>
      !_submitting && _selected != null && _qty > 0 && _reason != null;

  void _pickProduct() {
    final searchC = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          // Alifbodan qat'i nazar: «choy» ↔ «чой» (searchFold).
          final q = searchFold(searchC.text);
          final filtered = q.isEmpty
              ? _products
              : _products
                  .where((p) => searchFold(_productName(p)).contains(q))
                  .toList();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(context.gutter, 14, context.gutter, 8),
                  child: TextField(
                    controller: searchC,
                    onChanged: (_) => setSheet(() {}),
                    decoration: InputDecoration(
                      hintText: 'Mahsulot izlash...',
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppColors.textMuted),
                      suffixIcon: searchC.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                searchC.clear();
                                setSheet(() {});
                              },
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const EmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'Hech narsa topilmadi',
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(context.gutter, 4, context.gutter, 16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, color: AppColors.borderSoft),
                          itemBuilder: (_, i) {
                            final p = filtered[i] as Map<String, dynamic>;
                            return ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              leading: const IconAvatar(
                                icon: Icons.fastfood_rounded,
                                color: AppColors.primary,
                                size: 36,
                              ),
                              title: Text(
                                _productName(p),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                              trailing: Text(
                                '${formatMoney(p['price'])} so\'m',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textFaint,
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                setState(() => _selected = p);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      // Pop bo'lishi bilan future tugaydi, lekin yopilish animatsiyasi hali
      // TextField'ni chizib turadi. Darhol dispose qilinsa "controller used
      // after disposed" bilan butun ekran buzilardi (mahsulot qidirib
      // tanlanganda). Animatsiya tugashini kutib, keyin bo'shatamiz.
      Future.delayed(const Duration(milliseconds: 600), searchC.dispose);
    });
  }

  Future<void> _confirmAndSubmit() async {
    final p = _selected!;
    final qty = _qty;
    final reason = _reason!;
    final note = _noteC.text.trim();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Spisaniya tasdiqlash'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _productName(p),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text('Miqdor: $qty ta'),
            Text('Sabab: $reason'),
            if (note.isNotEmpty) Text('Izoh: $note'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Tasdiqlash'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final res = await ApiService().createWriteOff(
        (p['id'] as num).toInt(),
        qty,
        reason,
        note.isEmpty ? null : note,
      );
      if (!mounted) return;
      final newCount = res['new_count'];
      setState(() {
        _submitting = false;
        _selected = null;
        _reason = null;
        _qtyC.text = '1';
        _noteC.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newCount is num
              ? 'Spisaniya qilindi. Qoldiq: ${newCount.toInt()}'
              : 'Spisaniya qilindi (qoldiq cheksiz)'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadWriteOffs();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errMsg(e)), backgroundColor: AppColors.danger),
      );
    }
  }

  String _formatDate(dynamic v) {
    if (v == null) return '';
    final d = DateTime.tryParse(v.toString());
    if (d == null) return v.toString();
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text(
          'Spisaniya',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: TutorialHelpButton('pos.writeoff', size: 28),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadWriteOffs,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            _buildForm(),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'Oxirgi spisaniyalar',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
            ),
            if (_loadingList)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_writeOffs.isEmpty)
              const EmptyState(
                icon: Icons.delete_sweep_outlined,
                title: 'Spisaniyalar yo\'q',
                subtitle: 'Hisobdan chiqarilgan mahsulotlar shu yerda ko\'rinadi',
              )
            else
              ..._writeOffs
                  .map((w) => _buildWriteOffRow(w as Map<String, dynamic>)),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return KCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mahsulot',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Material(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: _pickProduct,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selected == null
                          ? Icons.fastfood_outlined
                          : Icons.fastfood_rounded,
                      size: 18,
                      color: _selected == null
                          ? AppColors.textMuted
                          : AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selected == null
                            ? 'Mahsulot tanlang'
                            : _productName(_selected),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: _selected == null
                              ? FontWeight.w600
                              : FontWeight.w800,
                          color: _selected == null
                              ? AppColors.textMuted
                              : AppColors.text,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.expand_more_rounded,
                        size: 20, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Miqdor',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _stepBtn(Icons.remove_rounded, () {
                final v = (int.tryParse(_qtyC.text.trim()) ?? 1) - 1;
                _qtyC.text = '${v < 1 ? 1 : v}';
                setState(() {});
              }),
              SizedBox(
                width: 76,
                child: TextField(
                  controller: _qtyC,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 10),
                    suffixText: 'ta',
                    suffixStyle: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                ),
              ),
              _stepBtn(Icons.add_rounded, () {
                final v = (int.tryParse(_qtyC.text.trim()) ?? 0) + 1;
                _qtyC.text = '$v';
                setState(() {});
              }),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Sabab',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in _reasons)
                ChoiceChip(
                  label: Text(r),
                  selected: _reason == r,
                  onSelected: (sel) =>
                      setState(() => _reason = sel ? r : null),
                  selectedColor: AppColors.danger.withValues(alpha: 0.14),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        _reason == r ? FontWeight.w800 : FontWeight.w600,
                    color:
                        _reason == r ? AppColors.danger : AppColors.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteC,
            decoration: const InputDecoration(
              labelText: 'Izoh (ixtiyoriy)',
              prefixIcon: Icon(Icons.notes_rounded, size: 18),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _canSubmit ? _confirmAndSubmit : null,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.delete_sweep_rounded, size: 18),
              label: const Text(
                'Spisaniya qilish',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWriteOffRow(Map<String, dynamic> w) {
    final qty = (w['qty'] as num?)?.toInt() ?? 0;
    final note = (w['note'] ?? '').toString();
    final byName = (w['created_by_name'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: KCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const IconAvatar(
              icon: Icons.delete_sweep_rounded,
              color: AppColors.danger,
              size: 36,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (w['product_name'] ?? '').toString(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${(w['reason'] ?? '').toString()}'
                    '${note.isNotEmpty ? ' — $note' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (byName.isNotEmpty) byName,
                      _formatDate(w['created_at']),
                    ].join(' • '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textFaint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '-$qty ta',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.danger,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}
