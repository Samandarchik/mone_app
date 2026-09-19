// shef/ui/cake_constructor_page.dart — tort konstruktori (CakeConstructorPage),
// shef bosh ekranidagi «П/Ф Бисквит» kartasidan ochiladi (shef_tech_card_page.dart →
// ShefTechCardProductsPage.showCakeConstructor). 6 qadam: Shakl → Ta'm → Rang →
// Toppinglar → Yozuv → Qo'shimchalar. Tepada «Jami» (tanlanganlar yig'indisi), qadamlar
// chizig'i (bosib istalgan qadamga o'tish mumkin), 3D tort (har tanlov darhol
// ko'rinadi; «Yozuv» qadamida aylanish to'xtab, tepadan ko'rinadi), pastda
// «‹» / «Keyingi». Oxirida — xulosa oynasi (ulashish / yangi tort).
// Katalog va narxlar — model/cake_design.dart (hozircha lokal, backend'siz).
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uz_ai_dev/shef/model/cake_design.dart';
import 'package:uz_ai_dev/shef/ui/widgets/cake_3d.dart';

const Color _ink = Color(0xFF2E2A4F);
const Color _lav = Color(0xFF9B8FCB);
const Color _lavLight = Color(0xFFEDE9F7);
const Color _selectedBg = Color(0xFFF1EEF8);
const Color _muted = Color(0xFF8B86A3);

const List<String> _stepNames = [
  'Shakl',
  'Ta\'m',
  'Rang',
  'Toppinglar',
  'Yozuv',
  'Qo\'shimchalar',
];

const List<String> _textIdeas = [
  'Tug\'ilgan kuning muborak!',
  'Happy Birthday',
  'Tabriklaymiz!',
  'Sevgi bilan',
];

class CakeConstructorPage extends StatefulWidget {
  const CakeConstructorPage({super.key});

  @override
  State<CakeConstructorPage> createState() => _CakeConstructorPageState();
}

class _CakeConstructorPageState extends State<CakeConstructorPage> {
  CakeDesign _d = CakeDesign();
  int _step = 0;
  bool _roundTab = true;
  final TextEditingController _textCtrl = TextEditingController();

  bool get _isLast => _step == _stepNames.length - 1;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _goTo(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
  }

  void _next() {
    if (_isLast) {
      _showSummary();
    } else {
      _goTo(_step + 1);
    }
  }

  void _back() {
    if (_step == 0) {
      Navigator.pop(context);
    } else {
      _goTo(_step - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom > 0;
    final previewH = keyboard
        ? 140.0
        : (media.size.height * 0.28).clamp(170.0, 300.0);
    return PopScope(
      // Tizim «orqaga» tugmasi — oldingi qadamga.
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(_step - 1);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _header(),
              _stepper(),
              const SizedBox(height: 8),
              Cake3DView(
                look: _d.look,
                height: previewH,
                borderRadius: BorderRadius.zero,
                faceFront: _step == 4,
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: _stepBody(),
                  ),
                ),
              ),
              if (!keyboard) _bottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new, color: _ink, size: 22),
          ),
          const Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Konstruktor',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _lavLight, width: 1.5),
            ),
            child: Text.rich(
              TextSpan(
                style: const TextStyle(color: _muted, fontSize: 14),
                children: [
                  const TextSpan(text: 'Jami: '),
                  TextSpan(
                    text: formatSom(_d.total),
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const TextSpan(text: ' UZS', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepper() {
    Widget line(bool visible, bool done) => Expanded(
          child: Container(
            height: 1.5,
            color: visible ? (done ? _lav : _lavLight) : Colors.transparent,
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          for (var i = 0; i < _stepNames.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _goTo(i),
                child: Column(
                  children: [
                    Row(
                      children: [
                        line(i > 0, i <= _step),
                        _stepCircle(i),
                        line(i < _stepNames.length - 1, i < _step),
                      ],
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _stepNames[i],
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight:
                              i == _step ? FontWeight.w700 : FontWeight.w500,
                          color: i == _step ? _ink : _muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stepCircle(int i) {
    final active = i == _step;
    final done = i < _step;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? _ink : (done ? _lavLight : Colors.white),
        border: Border.all(
          color: active ? _ink : _lav.withValues(alpha: done ? 1 : 0.55),
          width: 1.5,
        ),
      ),
      child: done
          ? const Icon(Icons.check, size: 16, color: _ink)
          : Text(
              '${i + 1}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : _muted,
              ),
            ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return _shapeStep();
      case 1:
        return _flavorStep();
      case 2:
        return _colorStep();
      case 3:
        return _addonStep(CakeCatalog.toppings, _d.toppingIds, grid: true);
      case 4:
        return _textStep();
      default:
        return _addonStep(CakeCatalog.extras, _d.extraIds, grid: false);
    }
  }

  // ─── 1. Shakl ───────────────────────────────────────────────────────────
  Widget _shapeStep() {
    Widget tab(String label, bool round) {
      final on = _roundTab == round;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _roundTab = round),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? _ink : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : _lav,
              ),
            ),
          ),
        ),
      );
    }

    final shapes =
        CakeCatalog.shapes.where((s) => s.isRound == _roundTab).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      children: [
        Container(
          height: 46,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: _lavLight,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              tab('Yumaloq', true),
              tab('Boshqa shakllar', false),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.6,
          children: [
            for (final s in shapes)
              _OptionCard(
                selected: _d.shape.id == s.id,
                badge: s.hit ? 'Хит' : null,
                onTap: () => setState(() => _d.shape = s),
                child: Column(
                  children: [
                    Expanded(
                      child: Cake3D(
                        tilt: 0.3,
                        look: CakeLook(
                          shape: s.shape,
                          scale: s.scale,
                          color: _d.color.color,
                          decos: const {},
                        ),
                      ),
                    ),
                    Text(
                      s.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    Text('${s.persons} kishilik', style: _mutedStyle),
                    Text('${s.diameterSm} sm', style: _mutedStyle),
                    const SizedBox(height: 2),
                    _price(s.price),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ─── 2. Ta'm ────────────────────────────────────────────────────────────
  Widget _flavorStep() {
    return GridView.count(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.25,
      children: [
        for (final f in CakeCatalog.flavors)
          _OptionCard(
            selected: _d.flavor.id == f.id,
            onTap: () => setState(() => _d.flavor = f),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FlavorSlice(color: f.color),
                const SizedBox(height: 6),
                Text(
                  f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                Expanded(
                  child: Text(
                    f.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _mutedStyle,
                  ),
                ),
                _price(f.price),
              ],
            ),
          ),
      ],
    );
  }

  // ─── 3. Rang ────────────────────────────────────────────────────────────
  Widget _colorStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: [
        const Text(
          'Tort qoplamasi rangi',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 14,
          children: [
            for (final c in CakeCatalog.colors)
              _ColorDot(
                option: c,
                size: 54,
                selected: _d.color.id == c.id,
                onTap: () => setState(() => _d.color = c),
              ),
          ],
        ),
      ],
    );
  }

  // ─── 4. Toppinglar / 6. Qo'shimchalar ───────────────────────────────────
  Widget _addonStep(
    List<AddonOption> options,
    Set<String> selected, {
    required bool grid,
  }) {
    void toggle(AddonOption a) => setState(() {
          if (!selected.remove(a.id)) selected.add(a.id);
        });

    if (grid) {
      return GridView.count(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.05,
        children: [
          for (final a in options)
            _OptionCard(
              selected: selected.contains(a.id),
              onTap: () => toggle(a),
              child: Column(
                children: [
                  Expanded(
                    child: a.deco == null
                        ? Icon(a.icon, color: _lav, size: 40)
                        : Cake3D(
                            tilt: 0.42,
                            look: CakeLook(
                              scale: 0.9,
                              color: _d.color.color,
                              decos: {a.deco!},
                            ),
                          ),
                  ),
                  Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  _price(a.price),
                ],
              ),
            ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      itemCount: options.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final a = options[i];
        return _OptionCard(
          selected: selected.contains(a.id),
          onTap: () => toggle(a),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: _lavLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(a.icon, color: _ink, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  a.name,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
              ),
              _price(a.price),
              const SizedBox(width: 30),
            ],
          ),
        );
      },
    );
  }

  // ─── 5. Yozuv ───────────────────────────────────────────────────────────
  Widget _textStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        TextField(
          controller: _textCtrl,
          maxLength: CakeCatalog.inscriptionMaxLength,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) => setState(() => _d.text = v),
          style: const TextStyle(color: _ink, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Tortdagi yozuv, masalan: Tabriklaymiz!',
            hintStyle: const TextStyle(color: _muted),
            filled: true,
            fillColor: _lavLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            suffixIcon: _d.hasText
                ? IconButton(
                    icon: const Icon(Icons.close, color: _muted),
                    onPressed: () => setState(() {
                      _textCtrl.clear();
                      _d.text = '';
                    }),
                  )
                : null,
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in _textIdeas)
              ActionChip(
                label: Text(t, style: const TextStyle(fontSize: 12.5)),
                backgroundColor: Colors.white,
                side: const BorderSide(color: _lavLight),
                onPressed: () => setState(() {
                  _textCtrl.text = t;
                  _d.text = t;
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Yozuv rangi',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in CakeCatalog.textColors)
              _ColorDot(
                option: c,
                size: 42,
                selected: _d.textColor.id == c.id,
                onTap: () => setState(() => _d.textColor = c),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Yozuv: +${formatSom(CakeCatalog.inscriptionPrice)} UZS '
          '(bo\'sh qolsa — qo\'shilmaydi)',
          style: _mutedStyle,
        ),
      ],
    );
  }

  Widget _bottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            height: 58,
            child: OutlinedButton(
              onPressed: _back,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: BorderSide(color: Colors.grey.shade200),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Icon(Icons.chevron_left, color: _ink, size: 30),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 58,
              child: ElevatedButton(
                onPressed: _next,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _lav,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(29),
                  ),
                ),
                child: Text(
                  _isLast ? 'Tayyor' : 'Keyingi',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Xulosa ─────────────────────────────────────────────────────────────
  List<(String, String, int)> _summaryLines() {
    final d = _d;
    return [
      (
        'Shakl',
        '${d.shape.name} · ${d.shape.persons} kishilik · ${d.shape.diameterSm} sm',
        d.shape.price,
      ),
      ('Ta\'m', d.flavor.name, d.flavor.price),
      ('Rang', d.color.name, d.color.price),
      for (final t in d.toppings) ('Topping', t.name, t.price),
      if (d.hasText)
        ('Yozuv', '«${d.text.trim()}» (${d.textColor.name.toLowerCase()})',
            CakeCatalog.inscriptionPrice),
      for (final e in d.extras) ('Qo\'shimcha', e.name, e.price),
    ];
  }

  Future<void> _share() async {
    final b = StringBuffer('🎂 Tort buyurtmasi\n');
    for (final (label, value, price) in _summaryLines()) {
      b.write('$label: $value');
      if (price > 0) b.write(' — ${formatSom(price)} UZS');
      b.write('\n');
    }
    b.write('Jami: ${formatSom(_d.total)} UZS');
    await SharePlus.instance.share(ShareParams(text: b.toString()));
  }

  void _showSummary() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            const Center(
              child: Text(
                'Sizning tortingiz',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
            ),
            SizedBox(height: 170, child: Cake3D(look: _d.look, tilt: 0.4)),
            for (final (label, value, price) in _summaryLines())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(label, style: _mutedStyle),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                    ),
                    Text(
                      price > 0 ? '${formatSom(price)} UZS' : '—',
                      style: const TextStyle(fontSize: 13.5, color: _ink),
                    ),
                  ],
                ),
              ),
            const Divider(height: 24),
            Row(
              children: [
                const Text(
                  'Jami',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const Spacer(),
                Text(
                  '${formatSom(_d.total)} UZS',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _textCtrl.clear();
                      setState(() {
                        _d = CakeDesign();
                        _step = 0;
                        _roundTab = true;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ink,
                      minimumSize: const Size.fromHeight(52),
                      side: const BorderSide(color: _lavLight, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Yangi tort'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _share,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _lav,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Ulashish'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const TextStyle _mutedStyle = TextStyle(fontSize: 12, color: _muted);

Widget _price(int price) => Text(
      price > 0 ? '+${formatSom(price)} UZS' : 'Narxga kirgan',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: price > 0 ? 13.5 : 12,
        fontWeight: FontWeight.w800,
        color: price > 0 ? _lav : _muted,
      ),
    );

// Tanlanadigan karta: tanlanganda och binafsha fon + ✓ belgisi.
class _OptionCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String? badge;

  const _OptionCard({
    required this.selected,
    required this.onTap,
    required this.child,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? _selectedBg : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _lav.withValues(alpha: 0.5) : _lavLight,
            width: 1.2,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            if (badge != null)
              Positioned(
                top: -2,
                left: -2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _lav.withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ),
              ),
            if (selected)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: _lav,
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.check, size: 16, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Ta'm kartasidagi kesim: biskvit / krem / biskvit qatlamlari.
class _FlavorSlice extends StatelessWidget {
  final Color color;

  const _FlavorSlice({required this.color});

  @override
  Widget build(BuildContext context) {
    final cream = Color.lerp(color, Colors.white, 0.75)!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 54,
        height: 34,
        child: Column(
          children: [
            Expanded(flex: 3, child: Container(color: color)),
            Expanded(flex: 2, child: Container(color: cream)),
            Expanded(flex: 3, child: Container(color: color)),
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final ColorOption option;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.option,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size + 18,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: size,
              height: size,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _ink : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: option.color,
                  border: Border.all(color: Colors.black12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              option.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? _ink : _muted,
              ),
            ),
            if (option.price > 0)
              Text(
                '+${formatSom(option.price)}',
                style: const TextStyle(fontSize: 10.5, color: _lav),
              ),
          ],
        ),
      ),
    );
  }
}
