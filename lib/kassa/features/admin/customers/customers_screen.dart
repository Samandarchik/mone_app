import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../widgets/admin_page.dart';
import '../widgets/admin_widgets.dart';
import '../../../core/utils/order_number.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _api = ApiService();
  final _search = TextEditingController();
  Timer? _searchTimer;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _promos = [];
  Map<String, dynamic> _summary = {};

  /// 0 — mijozlar, 1 — promo-kodlar.
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait<dynamic>([
        _api.getCustomers(search: _search.text),
        _api.getPromos(),
      ]);
      final customerData = Map<String, dynamic>.from(results[0] as Map);
      if (!mounted) return;
      setState(() {
        _customers = _maps(customerData['items']);
        _summary = _map(customerData['summary']);
        _promos = _maps(results[1]);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorMessage(error);
      });
    }
  }

  void _onSearch(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _editCustomer([Map<String, dynamic>? customer]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _CustomerFormDialog(customer: customer),
    );
    if (changed == true) await _load(quiet: true);
  }

  Future<void> _openCustomer(Map<String, dynamic> customer) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CustomerDetailsDialog(
        customerID: _int(customer['id']),
        onChanged: () => _load(quiet: true),
      ),
    );
  }

  Future<void> _editPromo([Map<String, dynamic>? promo]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _PromoFormDialog(promo: promo),
    );
    if (changed == true) await _load(quiet: true);
  }

  Future<void> _archivePromo(Map<String, dynamic> promo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Promo kodni arxivlash'),
        content: Text('${promo['code']} boshqa ishlamaydi. Davom etilsinmi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Arxivlash'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deletePromo(_int(promo['id']));
      await _load(quiet: true);
    } catch (error) {
      if (mounted) _snack(context, _errorMessage(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      subtitle: _tab == 0
          ? '${_int(_summary['total_customers'])} mijoz · '
              '${_int(_summary['active_30_days'])} tasi 30 kunda faol'
          : '${_promos.length} ta promo-kod',
      loading: _loading,
      error: _error,
      onRetry: _load,
      onRefresh: () => _load(quiet: true),
      searchController: _search,
      onSearchChanged: _onSearch,
      searchHint: 'Ism yoki telefon…',
      segments: const ['Mijozlar', 'Promo-kodlar'],
      segmentIndex: _tab,
      onSegmentChanged: (i) => setState(() => _tab = i),
      primaryAction: _tab == 0
          ? AdminAction(
              label: 'Mijoz qo‘shish',
              icon: Icons.person_add_alt_1_rounded,
              onPressed: _editCustomer,
              color: const Color(0xFFDB2777),
            )
          : AdminAction(
              label: 'Promo yaratish',
              icon: Icons.local_offer_rounded,
              onPressed: _editPromo,
              color: AppColors.warning,
            ),
      toolbar: _tab == 0 ? _buildSummary() : null,
      child: _tab == 0 ? _buildCustomers() : _buildPromos(),
    );
  }

  Widget _buildSummary() {
    return AdminStatsRow(
      items: [
        AdminStatData(
          label: 'JAMI MIJOZ',
          value: '${_int(_summary['total_customers'])}',
          icon: Icons.groups_2_rounded,
          color: AppColors.primary,
        ),
        AdminStatData(
          label: '30 KUNDA FAOL',
          value: '${_int(_summary['active_30_days'])}',
          icon: Icons.event_available_rounded,
          color: AppColors.success,
        ),
        AdminStatData(
          label: 'JAMI XARID',
          value: _money(_summary['total_spent']),
          icon: Icons.payments_rounded,
          color: AppColors.info,
        ),
        AdminStatData(
          label: 'BALL MAJBURIYATI',
          value: _money(_int(_summary['outstanding_points']) * 100),
          icon: Icons.stars_rounded,
          color: AppColors.warning,
        ),
      ],
    );
  }

  Widget _buildCustomers() {
    if (_customers.isEmpty) {
      return const _EmptyState(
        icon: Icons.people_outline_rounded,
        title: 'Mijozlar topilmadi',
        subtitle: 'Yangi mijoz qo‘shing yoki qidiruvni o‘zgartiring.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 850) {
          return Card(
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              child: SizedBox(
                width: double.infinity,
                child: DataTable(
                  showCheckboxColumn: false,
                  headingRowColor: WidgetStateProperty.all(
                    AppColors.surfaceAlt,
                  ),
                  columns: const [
                    DataColumn(label: Text('MIJOZ')),
                    DataColumn(label: Text('TELEFON')),
                    DataColumn(label: Text('TASHRIF')),
                    DataColumn(label: Text('JAMI XARID')),
                    DataColumn(label: Text('BALL')),
                    DataColumn(label: Text('OXIRGI TASHRIF')),
                    DataColumn(label: Text('')),
                  ],
                  rows: _customers.map((customer) {
                    return DataRow(
                      onSelectChanged: (_) => _openCustomer(customer),
                      cells: [
                        DataCell(_CustomerName(customer: customer)),
                        DataCell(Text(_phone(customer['phone']))),
                        DataCell(Text('${_int(customer['visit_count'])}')),
                        DataCell(Text(_money(customer['total_spent']))),
                        DataCell(
                          _PointsBadge(
                            points: _int(customer['loyalty_points']),
                          ),
                        ),
                        DataCell(Text(_shortDate(customer['last_visit_at']))),
                        DataCell(
                          IconButton(
                            onPressed: () => _editCustomer(customer),
                            icon: const Icon(Icons.edit_outlined, size: 19),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          );
        }
        return AdminList(
          children: [
            for (final customer in _customers)
              AdminTile(
                title: customer['name']?.toString().trim().isNotEmpty == true
                    ? customer['name'].toString()
                    : 'Nomsiz mijoz',
                subtitle: '${_phone(customer['phone'])} · '
                    '${_int(customer['visit_count'])} tashrif · '
                    '${_money(customer['total_spent'])}',
                initials: _initialsOf(customer['name']?.toString() ?? ''),
                color: const Color(0xFFDB2777),
                badge: _PointsBadge(
                  points: _int(customer['loyalty_points']),
                ),
                onTap: () => _openCustomer(customer),
                menu: const [
                  AdminMenuItem(
                    value: 'edit',
                    label: 'Tahrirlash',
                    icon: Icons.edit_outlined,
                  ),
                ],
                onMenuSelected: (_) => _editCustomer(customer),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPromos() {
    if (_promos.isEmpty) {
      return const _EmptyState(
        icon: Icons.local_offer_outlined,
        title: 'Promo kodlar yo‘q',
        subtitle: 'Chegirma kampaniyasini yarating.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.only(top: 14, bottom: 96),
      // 420: telefonda bitta ustun. 380 da ikki tor ustun bo'lib, kod,
      // summa va «ishlatilgan» qatori sig'masdi (overflow).
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 420,
        mainAxisExtent: 210,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _promos.length,
      itemBuilder: (context, index) {
        final promo = _promos[index];
        final active = promo['status'] == 'active';
        final percent = promo['discount_type'] == 'percent';
        final limit = promo['usage_limit'];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.successSoft
                            : AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        promo['code']?.toString() ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          color: active
                              ? AppColors.success
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _editPromo(promo);
                        if (value == 'delete') _archivePromo(promo);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Tahrirlash')),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Arxivlash'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  percent
                      ? '${_int(promo['value'])}% chegirma'
                      : '${_money(promo['value'])} chegirma',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Minimal buyurtma: ${_money(promo['min_order_total'])}',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                const Spacer(),
                Row(
                  children: [
                    const Icon(
                      Icons.confirmation_number_outlined,
                      size: 17,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        limit == null
                            ? '${_int(promo['used_count'])} marta ishlatilgan'
                            : '${_int(promo['used_count'])} / ${_int(limit)} ishlatilgan',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    _StatusDot(active: active),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CustomerDetailsDialog extends StatefulWidget {
  const _CustomerDetailsDialog({
    required this.customerID,
    required this.onChanged,
  });

  final int customerID;
  final VoidCallback onChanged;

  @override
  State<_CustomerDetailsDialog> createState() => _CustomerDetailsDialogState();
}

class _CustomerDetailsDialogState extends State<_CustomerDetailsDialog> {
  Map<String, dynamic>? _customer;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final customer = await ApiService().getCustomer(widget.customerID);
      if (mounted) setState(() => _customer = customer);
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    }
  }

  Future<void> _points(String type) async {
    final pointsController = TextEditingController();
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(type == 'earn' ? 'Ball qo‘shish' : 'Ball ishlatish'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pointsController,
                keyboardType: TextInputType.number,
                inputFormatters: const [MoneyInputFormatter()],
                decoration: const InputDecoration(labelText: 'Ball miqdori'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Izoh'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Saqlash'),
          ),
        ],
      ),
    );
    final points = parseIntField(pointsController.text) ?? 0;
    final note = noteController.text;
    pointsController.dispose();
    noteController.dispose();
    if (confirmed != true || points <= 0) return;
    try {
      await ApiService().updateCustomerLoyalty(
        widget.customerID,
        type: type,
        points: points,
        note: note,
      );
      await _load();
      widget.onChanged();
    } catch (error) {
      if (mounted) _snack(context, _errorMessage(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 760),
        child: _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : _customer == null
            ? const Center(child: CircularProgressIndicator())
            : _content(),
      ),
    );
  }

  Widget _content() {
    final customer = _customer!;
    final transactions = _maps(customer['transactions']);
    final orders = _maps(customer['orders']);
    final name = customer['name']?.toString().trim() ?? '';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 14, 14),
          child: Row(
            children: [
              _Avatar(name: name, large: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Nomsiz mijoz' : name,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _phone(customer['phone']),
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _DetailMetric(
                    label: 'Bonus ballari',
                    value: '${_int(customer['loyalty_points'])}',
                    icon: Icons.stars_rounded,
                    color: AppColors.warning,
                  ),
                  _DetailMetric(
                    label: 'Jami xarid',
                    value: _money(customer['total_spent']),
                    icon: Icons.payments_rounded,
                    color: AppColors.success,
                  ),
                  _DetailMetric(
                    label: 'Tashriflar',
                    value: '${_int(customer['visit_count'])}',
                    icon: Icons.event_available_rounded,
                    color: AppColors.primary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _points('earn'),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: const Text('Ball qo‘shish'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _points('redeem'),
                      icon: const Icon(Icons.redeem_rounded),
                      label: const Text('Ball ishlatish'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _SectionTitle(title: 'Ball harakatlari'),
              const SizedBox(height: 8),
              if (transactions.isEmpty)
                const Text(
                  'Harakatlar yo‘q',
                  style: TextStyle(color: AppColors.textMuted),
                )
              else
                ...transactions.take(20).map((transaction) {
                  final points = _int(transaction['points']);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: points >= 0
                          ? AppColors.successSoft
                          : AppColors.dangerSoft,
                      child: Icon(
                        points >= 0 ? Icons.add_rounded : Icons.remove_rounded,
                        color: points >= 0
                            ? AppColors.success
                            : AppColors.danger,
                      ),
                    ),
                    title: Text(
                      transaction['note']?.toString().trim().isNotEmpty == true
                          ? transaction['note'].toString()
                          : transaction['type'].toString(),
                    ),
                    subtitle: Text(
                      '${shortOrderNumber(transaction['order_number'])} · '
                      '${_shortDate(transaction['created_at'])}',
                    ),
                    trailing: Text(
                      '${points >= 0 ? '+' : ''}$points',
                      style: TextStyle(
                        color: points >= 0
                            ? AppColors.success
                            : AppColors.danger,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 20),
              const _SectionTitle(title: 'Buyurtmalar'),
              const SizedBox(height: 8),
              if (orders.isEmpty)
                const Text(
                  'Bog‘langan buyurtmalar yo‘q',
                  style: TextStyle(color: AppColors.textMuted),
                )
              else
                ...orders
                    .take(20)
                    .map(
                      (order) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text(shortOrderNumber(order['order_number'])),
                        subtitle: Text(
                          '${_shortDate(order['created_at'])} · '
                          '${order['payment_method'] ?? '—'}',
                        ),
                        trailing: Text(
                          _money(order['total']),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomerFormDialog extends StatefulWidget {
  const _CustomerFormDialog({this.customer});

  final Map<String, dynamic>? customer;

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _birthday;

  /// Mijoz botda bergan kun/oy («12-mart»). To'liq sana yo'q bo'lsa ham
  /// admin buni ko'rib turishi kerak.
  String _knownBirthday = '';
  late final TextEditingController _tags;
  late final TextEditingController _notes;
  String _gender = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final customer = widget.customer ?? {};
    _name = TextEditingController(text: customer['name']?.toString() ?? '');
    _phone = TextEditingController(text: customer['phone']?.toString() ?? '');
    _birthday = TextEditingController(
      text: customer['birthday']?.toString() ?? '',
    );
    _knownBirthday = customer['birthday_label']?.toString() ?? '';
    _tags = TextEditingController(
      text: _list(customer['tags']).map((item) => item.toString()).join(', '),
    );
    _notes = TextEditingController(text: customer['notes']?.toString() ?? '');
    _gender = customer['gender']?.toString() ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _birthday.dispose();
    _tags.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'birthday': _birthday.text.trim(),
      'gender': _gender,
      'tags': _tags.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(),
      'notes': _notes.text.trim(),
    };
    try {
      if (widget.customer == null) {
        await ApiService().createCustomer(data);
      } else {
        await ApiService().updateCustomer(_int(widget.customer!['id']), data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _snack(context, _errorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.customer == null ? 'Yangi mijoz' : 'Mijozni tahrirlash',
      ),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Ism'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefon *',
                    hintText: '+998 90 123 45 67',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Telefon kiriting'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _birthday,
                  decoration: InputDecoration(
                    labelText: 'Tug‘ilgan sana',
                    hintText: 'YYYY-MM-DD',
                    // Mijoz botda faqat KUN va OYni bergan bo'lishi mumkin
                    // (yil so'ralmaydi) — maydon bo'sh ko'rinsa ham sana
                    // ma'lum ekanini ko'rsatamiz.
                    helperText: _knownBirthday.isEmpty
                        ? null
                        : 'Mijoz o‘zi bergan: $_knownBirthday (yilsiz)',
                    helperStyle: const TextStyle(color: Color(0xFFDB2777)),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: const InputDecoration(labelText: 'Jins'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Ko‘rsatilmagan')),
                    DropdownMenuItem(value: 'male', child: Text('Erkak')),
                    DropdownMenuItem(value: 'female', child: Text('Ayol')),
                  ],
                  onChanged: (value) => _gender = value ?? '',
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _tags,
                  decoration: const InputDecoration(
                    labelText: 'Teglar',
                    hintText: 'VIP, tug‘ilgan kun, doimiy',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Izoh'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Bekor'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saqlanmoqda…' : 'Saqlash'),
        ),
      ],
    );
  }
}

class _PromoFormDialog extends StatefulWidget {
  const _PromoFormDialog({this.promo});

  final Map<String, dynamic>? promo;

  @override
  State<_PromoFormDialog> createState() => _PromoFormDialogState();
}

class _PromoFormDialogState extends State<_PromoFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _value;
  late final TextEditingController _minimum;
  late final TextEditingController _maximum;
  late final TextEditingController _limit;
  String _type = 'percent';
  bool _active = true;
  DateTime? _startsAt;
  DateTime? _endsAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final promo = widget.promo ?? {};
    _code = TextEditingController(text: promo['code']?.toString() ?? '');
    _value = TextEditingController(text: promo['value']?.toString() ?? '');
    _minimum = TextEditingController(
      text: promo['min_order_total']?.toString() ?? '0',
    );
    _maximum = TextEditingController(
      text: promo['max_discount']?.toString() ?? '',
    );
    _limit = TextEditingController(
      text: promo['usage_limit']?.toString() ?? '',
    );
    _type = promo['discount_type']?.toString() ?? 'percent';
    _active = promo.isEmpty || promo['status'] == 'active';
    _startsAt = DateTime.tryParse(promo['starts_at']?.toString() ?? '');
    _endsAt = DateTime.tryParse(promo['ends_at']?.toString() ?? '');
  }

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _minimum.dispose();
    _maximum.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool start) async {
    final current = start ? _startsAt : _endsAt;
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: current?.toLocal() ?? DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      final value = DateTime(
        picked.year,
        picked.month,
        picked.day,
        start ? 0 : 23,
        start ? 0 : 59,
        start ? 0 : 59,
      ).toUtc();
      if (start) {
        _startsAt = value;
      } else {
        _endsAt = value;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;

    // Har bir raqamli maydon ALOHIDA tekshiriladi.
    //
    // Ilgari o'qib bo'lmagan qiymat jimgina "xavfsiz" ko'ringan qiymatga
    // aylanardi va aksiya butunlay boshqacha ishlardi:
    //   min_order_total → 0   : 8 000 so'mlik choyga ham chegirma tushardi
    //   max_discount    → null: 30% chegirma 900 000 dan 270 000 kesardi
    //   usage_limit     → null: 100 martaga mo'ljallangan kod cheksiz bo'lardi
    final value = parseIntField(_value.text);
    final minimum = _minimum.text.trim().isEmpty ? 0 : parseIntField(_minimum.text);
    final maximum = _maximum.text.trim().isEmpty ? null : parseIntField(_maximum.text);
    final limit = _limit.text.trim().isEmpty ? null : parseIntField(_limit.text);
    final bad = value == null || value <= 0
        ? 'Chegirma qiymati'
        : minimum == null
            ? 'Minimal buyurtma summasi'
            : (_maximum.text.trim().isNotEmpty && maximum == null)
                ? 'Maksimal chegirma'
                : (_limit.text.trim().isNotEmpty && limit == null)
                    ? 'Ishlatish limiti'
                    : null;
    if (bad != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$bad faqat butun son bo‘lishi kerak'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    if (_type == 'percent' && value! > 100) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Foiz 100 dan oshmasligi kerak'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    setState(() => _saving = true);
    final data = <String, dynamic>{
      'code': _code.text.trim().toUpperCase(),
      'discount_type': _type,
      'value': value,
      'min_order_total': minimum,
      'max_discount': maximum,
      'usage_limit': limit,
      'starts_at': _startsAt?.toIso8601String() ?? '',
      'ends_at': _endsAt?.toIso8601String() ?? '',
      'status': _active ? 'active' : 'inactive',
    };
    try {
      if (widget.promo == null) {
        await ApiService().createPromo(data);
      } else {
        await ApiService().updatePromo(_int(widget.promo!['id']), data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _snack(context, _errorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.promo == null ? 'Yangi promo kod' : 'Promo kodni tahrirlash',
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Kod *',
                    hintText: 'YOZ2026',
                  ),
                  validator: (value) => value == null || value.trim().length < 3
                      ? 'Kamida 3 ta belgi'
                      : null,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _type,
                        decoration: const InputDecoration(
                          labelText: 'Chegirma turi',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'percent',
                            child: Text('Foiz'),
                          ),
                          DropdownMenuItem(
                            value: 'fixed',
                            child: Text('Belgilangan summa'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _type = value ?? 'percent'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _value,
                        keyboardType: TextInputType.number,
                        // Foizda ham zararsiz: probel 4-xonadan boshlanadi
                        inputFormatters: const [MoneyInputFormatter()],
                        decoration: InputDecoration(
                          labelText: _type == 'percent' ? 'Foiz *' : 'Summa *',
                        ),
                        validator: (value) {
                          final number = parseIntField(value) ?? 0;
                          if (number <= 0) return 'Qiymat kiriting';
                          if (_type == 'percent' && number > 100) {
                            return '100% dan oshmasin';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minimum,
                        keyboardType: TextInputType.number,
                        inputFormatters: const [MoneyInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Minimal buyurtma',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _maximum,
                        keyboardType: TextInputType.number,
                        inputFormatters: const [MoneyInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Maksimal chegirma',
                          hintText: 'Cheklanmagan',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _limit,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [MoneyInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Ishlatish limiti',
                    hintText: 'Cheklanmagan',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(true),
                        icon: const Icon(Icons.event_rounded),
                        label: Text(
                          _startsAt == null
                              ? 'Boshlanish'
                              : _shortDate(_startsAt),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(false),
                        icon: const Icon(Icons.event_busy_rounded),
                        label: Text(
                          _endsAt == null ? 'Tugash' : _shortDate(_endsAt),
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Faol'),
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Bekor'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saqlanmoqda…' : 'Saqlash'),
        ),
      ],
    );
  }
}

class _CustomerName extends StatelessWidget {
  const _CustomerName({required this.customer});

  final Map<String, dynamic> customer;

  @override
  Widget build(BuildContext context) {
    final name = customer['name']?.toString().trim() ?? '';
    return Row(
      children: [
        _Avatar(name: name),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            name.isEmpty ? 'Nomsiz mijoz' : name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.large = false});

  final String name;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: large ? 25 : 18,
      backgroundColor: const Color(0xFFFCE7F3),
      child: Text(
        letter,
        style: TextStyle(
          color: const Color(0xFFDB2777),
          fontWeight: FontWeight.w800,
          fontSize: large ? 19 : 14,
        ),
      ),
    );
  }
}

class _PointsBadge extends StatelessWidget {
  const _PointsBadge({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        '$points ball',
        style: const TextStyle(
          color: Color(0xFFB45309),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: active ? AppColors.success : AppColors.textFaint,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          active ? 'Faol' : 'Nofaol',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 218,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.text,
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: AppColors.textFaint),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 48),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Qayta urinish'),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

List<dynamic> _list(dynamic value) => value is List ? value : const [];

List<Map<String, dynamic>> _maps(dynamic value) =>
    _list(value).map(_map).toList();

int _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _money(dynamic value) {
  final raw = _int(value).toString();
  final output = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) output.write(' ');
    output.write(raw[i]);
  }
  return '${output.toString()} so‘m';
}

String _phone(dynamic value) {
  final raw = value?.toString() ?? '';
  if (raw.length == 12 && raw.startsWith('998')) {
    return '+${raw.substring(0, 3)} ${raw.substring(3, 5)} '
        '${raw.substring(5, 8)} ${raw.substring(8, 10)} ${raw.substring(10)}';
  }
  return raw;
}

String _shortDate(dynamic value) {
  final date = value is DateTime
      ? value
      : DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return '—';
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')}.${local.year}';
}

String _errorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return 'Server bilan aloqa yo‘q';
    }
  }
  return 'Amal bajarilmadi';
}

void _snack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.danger : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
}


/// Ism → bosh harflar (avatar uchun).
String _initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.elementAt(1).characters.first)
      .toUpperCase();
}
