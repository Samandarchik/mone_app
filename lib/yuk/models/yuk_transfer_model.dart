// Targovli (qilinadigan_ishlar) tizimidan yuk keltiruvchiga yuborilgan pul.
// Kassir u tomonda yuboradi; yuk keltiruvchi shu ilovada "Qabul qilish" yoki
// "Rad etish" qiladi. Qabul qilinsa summa kunlik hisob daftariga (ledger)
// prixod bo'lib tushadi va targovli tomonga "qabul qilindi" qaytariladi.
import 'package:uz_ai_dev/core/constants/urls.dart';

class YukTransfer {
  final int id;
  final int userId;
  final String userName;
  final double amount;
  // Kassir yozgan izoh (bo'sh bo'lishi mumkin).
  final String comment;
  // Targovli tomonda pulni yuborgan kassir ismi.
  final String senderName;
  // pending | accepted | rejected
  final String status;
  // Rad etish sababi (reject'da yoziladi).
  final String reviewText;
  final DateTime? created;
  // Chek rasmi — targovli serveridagi ABSOLYUT URL (bo'sh = rasmsiz).
  // Targovli «Онлайн» to'lovlari (masalan To'yxona) chek bilan keladi.
  final String imageUrl;
  // '' — kassir qo'lda yuborgan; 'online' — targovli «Онлайн» to'lovidan
  // avto (achyot yopilgach). Kartada «Onlayn to'lov» deb ko'rsatiladi.
  final String source;

  const YukTransfer({
    required this.id,
    required this.userId,
    required this.userName,
    required this.amount,
    this.comment = '',
    this.senderName = '',
    this.status = 'pending',
    this.reviewText = '',
    this.created,
    this.imageUrl = '',
    this.source = '',
  });

  bool get isPending => status == 'pending';
  bool get isOnline => source == 'online';
  bool get hasImage => imageUrl.isNotEmpty;

  // Rasm URL'i: absolyut bo'lsa o'z holicha, nisbiy bo'lsa mone serveriga.
  String get imageFullUrl =>
      imageUrl.startsWith('http') ? imageUrl : '${AppUrls.baseUrl}$imageUrl';

  factory YukTransfer.fromJson(Map<String, dynamic> json) => YukTransfer(
        id: (json['id'] as num?)?.toInt() ?? 0,
        userId: (json['user_id'] as num?)?.toInt() ?? 0,
        userName: json['user_name']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        comment: json['comment']?.toString() ?? '',
        senderName: json['sender_name']?.toString() ?? '',
        status: json['status']?.toString() ?? 'pending',
        reviewText: json['review_text']?.toString() ?? '',
        created: DateTime.tryParse(json['created']?.toString() ?? ''),
        imageUrl: json['image_url']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
      );
}

// GET /api/yuk/transfers javobidagi data ro'yxatini parse qiladi.
List<YukTransfer> parseYukTransfers(dynamic data) {
  if (data is! List) return [];
  return [
    for (final e in data)
      if (e is Map) YukTransfer.fromJson(Map<String, dynamic>.from(e)),
  ];
}
