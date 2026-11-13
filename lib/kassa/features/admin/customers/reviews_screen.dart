import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../widgets/admin_page.dart';
import '../widgets/admin_widgets.dart';

/// MIJOZ IZOHLARI — reyting, dinamika va shikoyatlarni nazorat qilish.
///
/// Izohlar ilgari ham yig'ilardi (mini-app → `/api/review`), lekin faqat
/// telegram guruhiga xabar bo'lib ketardi va yo'qolardi. Endi:
///   * o'rtacha baho va u o'sayaptimi/tushyaptimi ko'rinadi;
///   * past baholar alohida ajratiladi va «hal qilindi» deb belgilanadi;
///   * mijozga TELEGRAM ORQALI javob yozish mumkin.
class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

const _reviewAccent = Color(0xFFF59E0B);

class _ReviewsScreenState extends State<ReviewsScreen> {
  final _api = ApiService();
  final _search = TextEditingController();
  Timer? _searchTimer;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _trend = [];
  Map<String, dynamic> _summary = {};

  /// Oyna: 7 / 30 / 90 kun.
  int _days = 30;

  /// '' — hammasi, 'low' — past baho, 'high' — yuqori, 'todo' — hal qilinmagan.
  String _filter = '';

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
      final data = await _api.getReviews(
        days: _days,
        minRating: _filter == 'high' ? 4 : 0,
        maxRating: _filter == 'low' || _filter == 'todo' ? 3 : 0,
        unhandled: _filter == 'todo',
        search: _search.text,
      );
      if (!mounted) return;
      setState(() {
        _items = _maps(data['items']);
        _trend = _maps(data['trend']);
        _summary = _map(data['summary']);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorText(error);
      });
    }
  }

  void _onSearch(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(
      const Duration(milliseconds: 350),
      () => _load(quiet: true),
    );
  }

  void _setFilter(String value) {
    setState(() => _filter = _filter == value ? '' : value);
    unawaited(_load(quiet: true));
  }

  Future<void> _reply(Map<String, dynamic> review) async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => _ReplyDialog(review: review),
    );
    if (sent == true) {
      _snack('Javob mijozga yuborildi');
      await _load(quiet: true);
    }
  }

  Future<void> _toggleHandled(Map<String, dynamic> review) async {
    final handled = review['handled'] == true;
    try {
      await _api.setReviewHandled(_int(review['id']), !handled);
      await _load(quiet: true);
    } catch (error) {
      if (mounted) _snack(_errorText(error), error: true);
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.danger : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avg = _double(_summary['avg']);
    return AdminPage(
      title: 'Izohlar',
      icon: Icons.reviews_rounded,
      accent: _reviewAccent,
      subtitle: _int(_summary['count']) == 0
          ? 'Bu davrda izoh yo‘q'
          : '${_int(_summary['count'])} ta izoh · o‘rtacha ${avg.toStringAsFixed(2)}',
      loading: _loading,
      error: _error,
      onRetry: _load,
      onRefresh: () => _load(quiet: true),
      searchController: _search,
      onSearchChanged: _onSearch,
      searchHint: 'Izoh matni, ism, telefon yoki chek…',
      toolbar: _toolbar(),
      child: _buildList(),
    );
  }

  Widget _toolbar() {
    final avg = _double(_summary['avg']);
    final prev = _double(_summary['prev_avg']);
    final unhandled = _int(_summary['unhandled']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminStatsRow(
          items: [
            AdminStatData(
              label: 'O‘RTACHA BAHO',
              value: avg == 0 ? '—' : avg.toStringAsFixed(2),
              icon: Icons.star_rounded,
              color: _ratingColor(avg.round()),
            ),
            AdminStatData(
              label: 'IZOHLAR',
              value: '${_int(_summary['count'])}',
              icon: Icons.forum_rounded,
              color: AppColors.info,
            ),
            AdminStatData(
              label: 'PAST BAHO',
              value: '${_int(_summary['negative'])}',
              icon: Icons.thumb_down_rounded,
              color: AppColors.danger,
            ),
            AdminStatData(
              label: 'HAL QILINMAGAN',
              value: '$unhandled',
              icon: Icons.pending_actions_rounded,
              color: unhandled > 0 ? AppColors.warning : AppColors.success,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _RatingBars(
          stars: _map(_summary['stars']),
          total: _int(_summary['rated']),
          avg: avg,
          prevAvg: prev,
          trend: _trend,
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final d in const [7, 30, 90])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: KChip(
                    label: '$d kun',
                    selected: _days == d,
                    accent: AppColors.primary,
                    onTap: () {
                      setState(() => _days = d);
                      unawaited(_load(quiet: true));
                    },
                  ),
                ),
              const SizedBox(width: 8),
              KChip(
                label: 'Past baho',
                icon: Icons.thumb_down_outlined,
                selected: _filter == 'low',
                accent: AppColors.danger,
                onTap: () => _setFilter('low'),
              ),
              const SizedBox(width: 8),
              KChip(
                label: 'Hal qilinmagan',
                icon: Icons.pending_actions_outlined,
                selected: _filter == 'todo',
                accent: AppColors.warning,
                onTap: () => _setFilter('todo'),
              ),
              const SizedBox(width: 8),
              KChip(
                label: 'Yuqori baho',
                icon: Icons.thumb_up_outlined,
                selected: _filter == 'high',
                accent: AppColors.success,
                onTap: () => _setFilter('high'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    if (_items.isEmpty) {
      return AdminEmpty(
        icon: Icons.reviews_outlined,
        title: _filter.isEmpty ? 'Izoh yo‘q' : 'Bu filtrda izoh yo‘q',
        message: _filter.isEmpty
            ? 'Mijoz chek olgandan keyin «Izoh qoldirish» tugmasini bossa, '
                  'izoh shu yerda paydo bo‘ladi.'
            : 'Filtrni o‘zgartiring yoki davrni kengaytiring.',
        color: _reviewAccent,
      );
    }
    return AdminList(
      children: [
        for (final r in _items)
          _ReviewCard(
            review: r,
            onReply: () => _reply(r),
            onToggleHandled: () => _toggleHandled(r),
          ),
      ],
    );
  }
}

// ============================================================
// Reyting taqsimoti va dinamika
// ============================================================

class _RatingBars extends StatelessWidget {
  final Map<String, dynamic> stars;
  final int total;
  final double avg;
  final double prevAvg;
  final List<Map<String, dynamic>> trend;

  const _RatingBars({
    required this.stars,
    required this.total,
    required this.avg,
    required this.prevAvg,
    required this.trend,
  });

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, c) {
            final bars = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var star = 5; star >= 1; star--)
                  _bar(star, _int(stars['$star'])),
              ],
            );
            final delta = _DeltaLabel(avg: avg, prevAvg: prevAvg);
            // Tor ekranda ustma-ust, kengda yonma-yon.
            if (c.maxWidth < 620) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [delta, const SizedBox(height: 12), bars],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 200, child: delta),
                const SizedBox(width: 24),
                Expanded(child: bars),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _bar(int star, int count) {
    final ratio = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Row(
              children: [
                Text(
                  '$star',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.star_rounded, size: 14, color: _ratingColor(star)),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                backgroundColor: AppColors.surfaceAlt,
                valueColor: AlwaysStoppedAnimation(_ratingColor(star)),
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// O'rtacha baho + oldingi davr bilan farq. Reyting tushib ketayotganini
/// bir qarashda ko'rsatish uchun.
class _DeltaLabel extends StatelessWidget {
  final double avg;
  final double prevAvg;
  const _DeltaLabel({required this.avg, required this.prevAvg});

  @override
  Widget build(BuildContext context) {
    final diff = prevAvg == 0 ? 0.0 : avg - prevAvg;
    final up = diff > 0.05;
    final down = diff < -0.05;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              avg.toStringAsFixed(2),
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: _ratingColor(avg.round()),
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              '/ 5',
              style: TextStyle(fontSize: 15, color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (prevAvg > 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                up
                    ? Icons.trending_up_rounded
                    : down
                    ? Icons.trending_down_rounded
                    : Icons.trending_flat_rounded,
                size: 16,
                color: up
                    ? AppColors.success
                    : down
                    ? AppColors.danger
                    : AppColors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                up || down
                    ? '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(2)} oldingi davrga nisbatan'
                    : 'oldingi davr bilan bir xil',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: up
                      ? AppColors.success
                      : down
                      ? AppColors.danger
                      : AppColors.textMuted,
                ),
              ),
            ],
          )
        else
          const Text(
            'solishtirish uchun ma’lumot yo‘q',
            style: TextStyle(fontSize: 11, color: AppColors.textFaint),
          ),
      ],
    );
  }
}

// ============================================================
// Bitta izoh
// ============================================================

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  final VoidCallback onReply;
  final VoidCallback onToggleHandled;

  const _ReviewCard({
    required this.review,
    required this.onReply,
    required this.onToggleHandled,
  });

  @override
  Widget build(BuildContext context) {
    final rating = _int(review['rating']);
    final comment = _text(review['comment']);
    final reply = _text(review['reply_text']);
    final handled = review['handled'] == true;
    final canReply = review['can_reply'] == true;
    final low = rating > 0 && rating <= 3;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (rating > 0) _Stars(rating: rating),
                if (rating == 0)
                  const StatusBadge(
                    label: 'Bahosiz',
                    color: AppColors.textMuted,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _who(review),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  _shortDate(review['created_at']),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textFaint,
                  ),
                ),
              ],
            ),
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(comment, style: const TextStyle(fontSize: 14, height: 1.4)),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (_text(review['table_name']).isNotEmpty)
                  _meta(
                    Icons.table_restaurant_outlined,
                    _text(review['table_name']),
                  ),
                if (_text(review['order_number']).isNotEmpty)
                  _meta(
                    Icons.receipt_long_outlined,
                    '№ ${_text(review['order_number'])}',
                  ),
                if (_text(review['phone']).isNotEmpty)
                  _meta(Icons.phone_outlined, _text(review['phone'])),
                _meta(
                  review['source'] == 'tg'
                      ? Icons.telegram_rounded
                      : Icons.language_rounded,
                  review['source'] == 'tg' ? 'Telegram' : 'Sayt',
                ),
              ],
            ),
            if (reply.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: const Border(
                    left: BorderSide(color: Color(0xFF229ED9), width: 3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          review['reply_sent_at'] != null
                              ? Icons.done_all_rounded
                              : Icons.schedule_rounded,
                          size: 14,
                          color: review['reply_sent_at'] != null
                              ? AppColors.success
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          review['reply_sent_at'] != null
                              ? 'Javob yuborildi'
                              : 'Javob navbatda',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                          ),
                        ),
                        if (_text(review['reply_by']).isNotEmpty)
                          Text(
                            ' · ${_text(review['reply_by'])}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textFaint,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(reply, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            // Wrap: telefonda «Hal qilindi» belgisi + «Qaytadan ochish» +
            // «Javob berish» bitta qatorga sig'masdi (overflow) — o'tkaziladi.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (handled)
                  const StatusBadge(
                    label: 'Hal qilindi',
                    color: AppColors.success,
                    icon: Icons.check_circle_rounded,
                  )
                else if (low)
                  const StatusBadge(
                    label: 'E’tibor kerak',
                    color: AppColors.warning,
                    icon: Icons.priority_high_rounded,
                  ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: onToggleHandled,
                      icon: Icon(
                        handled
                            ? Icons.restart_alt_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 18,
                      ),
                      label: Text(handled ? 'Qaytadan ochish' : 'Hal qilindi'),
                      style: TextButton.styleFrom(
                        foregroundColor: handled
                            ? AppColors.textMuted
                            : AppColors.success,
                      ),
                    ),
                    if (canReply)
                      TextButton.icon(
                        onPressed: onReply,
                        icon: const Icon(Icons.reply_rounded, size: 18),
                        label: Text(
                          reply.isEmpty ? 'Javob berish' : 'Qayta javob',
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF229ED9),
                        ),
                      )
                    else
                      const Tooltip(
                        message: 'Telegramsiz izoh — javob yuborib bo‘lmaydi',
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Icon(
                            Icons.reply_rounded,
                            size: 18,
                            color: AppColors.textGhost,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: AppColors.textFaint),
      const SizedBox(width: 4),
      Text(
        text,
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
    ],
  );

  String _who(Map<String, dynamic> r) {
    final name = _text(r['name']);
    return name.isEmpty ? 'Mehmon' : name;
  }
}

class _Stars extends StatelessWidget {
  final int rating;
  const _Stars({required this.rating});

  @override
  Widget build(BuildContext context) {
    final color = _ratingColor(rating);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 15, color: color),
          const SizedBox(width: 3),
          Text(
            '$rating',
            style: TextStyle(
              fontSize: 13,
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
// Javob yozish
// ============================================================

class _ReplyDialog extends StatefulWidget {
  final Map<String, dynamic> review;
  const _ReplyDialog({required this.review});

  @override
  State<_ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends State<_ReplyDialog> {
  final _api = ApiService();
  late final TextEditingController _reply = TextEditingController(
    text: _text(widget.review['reply_text']),
  );
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  /// Tez javob namunalari — nol holatdan boshlash qiyin, tayyor matn
  /// tahrirlanadi.
  List<String> get _templates {
    final rating = _int(widget.review['rating']);
    if (rating > 0 && rating <= 3) {
      return const [
        'Uzr so‘raymiz! Bu holat uchun kechirim so‘raymiz — sababni aniqlab, '
            'tuzatdik. Keyingi tashrifingizda yaxshiroq xizmat ko‘rsatamiz.',
        'Fikringiz uchun rahmat. Muammoni jamoa bilan muhokama qildik. '
            'Iltimos, yana bir bor sinab ko‘ring — sizni kutamiz.',
      ];
    }
    return const [
      'Iliq so‘zlaringiz uchun rahmat! Sizni yana kutib qolamiz 🤍',
      'Rahmat! Fikringiz jamoamiz uchun juda muhim.',
    ];
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Javob matnini yozing');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _api.replyToReview(_int(widget.review['id']), text);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = _errorText(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final comment = _text(widget.review['comment']);
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.reply_rounded, color: Color(0xFF229ED9)),
          SizedBox(width: 10),
          Text('Mijozga javob'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Nimaga javob yozayotgani ko'rinib tursin.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (_int(widget.review['rating']) > 0)
                          _Stars(rating: _int(widget.review['rating'])),
                        const SizedBox(width: 8),
                        Text(
                          _text(widget.review['name']).isEmpty
                              ? 'Mehmon'
                              : _text(widget.review['name']),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    if (comment.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '«$comment»',
                        style: const TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _reply,
                maxLines: 5,
                minLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Javob matni',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _templates)
                    ActionChip(
                      label: Text(
                        t.length > 34 ? '${t.substring(0, 34)}…' : t,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onPressed: () => setState(() => _reply.text = t),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(
                    Icons.telegram_rounded,
                    size: 14,
                    color: AppColors.textFaint,
                  ),
                  SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Javob mijozning telegramiga, izohi bilan birga boradi.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context, false),
          child: const Text('Bekor'),
        ),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send_rounded, size: 18),
          label: Text(_sending ? 'Yuborilmoqda…' : 'Yuborish'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF229ED9),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// Yordamchilar
// ============================================================

Color _ratingColor(int rating) {
  if (rating >= 5) return AppColors.success;
  if (rating == 4) return const Color(0xFF84CC16);
  if (rating == 3) return _reviewAccent;
  if (rating == 2) return AppColors.warning;
  if (rating <= 0) return AppColors.textMuted;
  return AppColors.danger;
}

int _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double _double(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

String _text(dynamic value) => value == null ? '' : '$value'.trim();

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value.map((e) => Map<String, dynamic>.from(e as Map)).toList()
    : [];

String _shortDate(dynamic value) {
  final raw = _text(value);
  if (raw.isEmpty) return '—';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  final d = parsed.toLocal();
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return 'bugun ${two(d.hour)}:${two(d.minute)}';
  }
  return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}

String _errorText(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] != null) return '${data['message']}';
    if (data is Map && data['error'] != null) return '${data['error']}';
    return error.message ?? 'Tarmoq xatosi';
  }
  return '$error';
}
