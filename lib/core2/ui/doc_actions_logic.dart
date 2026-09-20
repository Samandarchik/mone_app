// core2/ui/doc_actions_logic.dart — hujjat kartasidagi «Tuzatish» va «Nusxa
// olish» amallarining SOF mantig'i (Flutter'ga bog'liq emas, to'g'ridan-
// to'g'ri test bilan qoplanadi: `test/core2_doc_actions_logic_test.dart`).
//
// CORE_DEBT_KONTRAKT §1–§2:
//  • «Tuzatish» (`POST /docs/{id}/rework`) — faqat O'TKAZILGAN hujjatda,
//    manbasi `sh5|sh5_import|rk7` BO'LMAGANDA (oyna/kassa hujjatini ilova
//    tuzata olmaydi), `doc.cancel` + `doc.<type>.create` ruxsati bilan;
//    orqa sanali hujjatda yana `doc.backdate`.
//  • «Nusxa olish» (`POST /docs/{id}/copy`) — har qanday holat va manbadan
//    (sh5/rk7 ham), sana default BUGUN → `doc.<type>.create` yetarli.
//  • Oyna/kassa hujjatlarida tugma o'rniga bir qatorli kulrang izoh.

/// Hujjat manbalari: hujjatning EGASI tashqi tizim (SH5 oynasi yoki kassa).
/// Bunday hujjat ilovadan tuzatilmaydi — faqat nusxa olinadi.
const Set<String> kCoreMirrorSources = {'sh5', 'sh5_import', 'rk7'};

/// Manba tashqi tizimnikimi (409 `mirror_owned` shu holatda qaytadi).
bool coreIsMirrorSource(String source) =>
    kCoreMirrorSources.contains(source.trim().toLowerCase());

/// Oyna/kassa hujjati uchun «nega tuzatib bo'lmaydi» izohi (kichik kulrang).
String coreMirrorNoteUz(String source) =>
    source.trim().toLowerCase() == 'rk7'
        ? 'Kassa sotuvi — tuzatilmaydi'
        : 'SH5 dan ko\'chirilgan hujjat — SH5 da tuzatiladi';

/// Manba → ro'yxat/filtr yorlig'i: Ilova / SH5 / Kassa.
String coreSourceUz(String source) {
  switch (source.trim().toLowerCase()) {
    case '':
    case 'app':
      return 'Ilova';
    case 'api':
      return 'API';
    case 'sh5':
      return 'SH5';
    case 'sh5_import':
      return 'SH5 (yuklangan)';
    case 'rk7':
      return 'Kassa';
    case 'konak':
      return 'Konak';
    default:
      return source;
  }
}

/// «Manba» filtri variantlari (kalit → yorliq).
const Map<String, String> coreSourceFilterOptions = {
  'app': 'Ilova',
  'sh5': 'SH5',
  'sh5_import': 'SH5 (yuklangan)',
  'rk7': 'Kassa',
};

/// Hujjat kartasida ko'rinadigan amallar.
class CoreDocActions {
  /// «Tuzatish» tugmasi ko'rinadimi.
  final bool rework;

  /// «Nusxa olish» tugmasi ko'rinadimi.
  final bool copy;

  /// Bo'sh emas bo'lsa: tugma o'rniga shu kulrang izoh ko'rsatiladi
  /// (oyna/kassa hujjati).
  final String mirrorNote;

  /// «Tuzatish» ruxsat yetishmagani uchun yashiringan bo'lsa — qaysi ruxsat
  /// kerak (bo'sh — sabab boshqa: holat yoki manba).
  final String missingPerm;

  const CoreDocActions({
    this.rework = false,
    this.copy = false,
    this.mirrorNote = '',
    this.missingPerm = '',
  });
}

/// Hujjat holati/manbasi/ruxsatlari bo'yicha amallar.
///
/// [backdated] — `doc_date` bugundan oldinmi (u holda `doc.backdate` kerak).
CoreDocActions coreDocActionsFor({
  required String status,
  required String source,
  required bool canCancel,
  required bool canCreateType,
  bool canBackdate = false,
  bool backdated = false,
}) {
  final mirror = coreIsMirrorSource(source);
  final posted = status == 'posted';
  // Nusxa — istalgan hujjatdan (sh5/rk7 ham), sana bugun → backdate kerak emas.
  final copy = canCreateType;
  if (!posted) {
    return CoreDocActions(copy: copy);
  }
  if (mirror) {
    return CoreDocActions(copy: copy, mirrorNote: coreMirrorNoteUz(source));
  }
  var missing = '';
  if (!canCancel) {
    missing = 'doc.cancel';
  } else if (!canCreateType) {
    missing = 'create';
  } else if (backdated && !canBackdate) {
    missing = 'doc.backdate';
  }
  return CoreDocActions(
    rework: missing.isEmpty,
    copy: copy,
    missingPerm: missing,
  );
}
