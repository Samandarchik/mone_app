// «Tuzatish» / «Nusxa olish» amallari: qaysi holat + manba + ruxsatda
// ko'rinadi (`lib/core2/ui/doc_actions_logic.dart`), xato tarjimoni
// (`core_labels.dart`: 409 `mirror_owned`, eski serverda yo'q endpoint) va
// yangi JSON maydonlari (`created_by_name`, `reworked_from`, `doc_index`).
import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/core2/core_labels.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';
import 'package:uz_ai_dev/core2/ui/doc_actions_logic.dart';

CoreDocActions _acts({
  String status = 'posted',
  String source = 'app',
  bool canCancel = true,
  bool canCreate = true,
  bool canBackdate = false,
  bool backdated = false,
}) =>
    coreDocActionsFor(
      status: status,
      source: source,
      canCancel: canCancel,
      canCreateType: canCreate,
      canBackdate: canBackdate,
      backdated: backdated,
    );

void main() {
  group('«Tuzatish» ko\'rinishi', () {
    test('o\'tkazilgan ilova hujjati + ikkala ruxsat — ko\'rinadi', () {
      final a = _acts();
      expect(a.rework, isTrue);
      expect(a.copy, isTrue);
      expect(a.mirrorNote, isEmpty);
    });

    test('qoralama va bekor qilinganda «Tuzatish» yo\'q', () {
      expect(_acts(status: 'draft').rework, isFalse);
      expect(_acts(status: 'cancelled').rework, isFalse);
      // Nusxa esa har qanday holatdan olinadi.
      expect(_acts(status: 'draft').copy, isTrue);
      expect(_acts(status: 'cancelled').copy, isTrue);
    });

    test('`doc.cancel` yoki `doc.<type>.create` yo\'q — yashiriladi', () {
      final noCancel = _acts(canCancel: false);
      expect(noCancel.rework, isFalse);
      expect(noCancel.missingPerm, 'doc.cancel');
      final noCreate = _acts(canCreate: false);
      expect(noCreate.rework, isFalse);
      expect(noCreate.copy, isFalse, reason: 'nusxa ham yaratish ruxsati');
    });

    test('orqa sanali hujjat — `doc.backdate` kerak', () {
      expect(_acts(backdated: true).rework, isFalse);
      expect(_acts(backdated: true).missingPerm, 'doc.backdate');
      expect(_acts(backdated: true, canBackdate: true).rework, isTrue);
      // Nusxa bugungi sana bilan olinadi — backdate kerak emas.
      expect(_acts(backdated: true).copy, isTrue);
    });
  });

  group('Oyna / kassa hujjatlari (mirror)', () {
    test('sh5, sh5_import, rk7 — tuzatilmaydi, izoh chiqadi', () {
      for (final s in ['sh5', 'sh5_import', 'rk7']) {
        final a = _acts(source: s);
        expect(a.rework, isFalse, reason: s);
        expect(a.copy, isTrue, reason: '$s — nusxa olinadi');
        expect(a.mirrorNote, isNotEmpty, reason: s);
      }
    });

    test('izoh matni: SH5 va kassa uchun har xil', () {
      expect(_acts(source: 'sh5').mirrorNote,
          'SH5 dan ko\'chirilgan hujjat — SH5 da tuzatiladi');
      expect(_acts(source: 'SH5_IMPORT').mirrorNote,
          'SH5 dan ko\'chirilgan hujjat — SH5 da tuzatiladi');
      expect(_acts(source: 'rk7').mirrorNote, 'Kassa sotuvi — tuzatilmaydi');
    });

    test('app / api / konak — oyna emas', () {
      for (final s in ['app', 'api', 'konak', '']) {
        expect(coreIsMirrorSource(s), isFalse, reason: s);
        expect(_acts(source: s).mirrorNote, isEmpty, reason: s);
      }
      expect(coreIsMirrorSource('sh5'), isTrue);
    });

    test('manba yorliqlari: Ilova / SH5 / Kassa', () {
      expect(coreSourceUz('app'), 'Ilova');
      expect(coreSourceUz(''), 'Ilova');
      expect(coreSourceUz('sh5'), 'SH5');
      expect(coreSourceUz('rk7'), 'Kassa');
      expect(coreSourceFilterOptions.keys.toList(),
          ['app', 'sh5', 'sh5_import', 'rk7']);
    });
  });

  group('Xato tarjimoni', () {
    test('409 mirror_owned — «o\'sha tizimda tuzatiladi»', () {
      final e = const CoreApiException(
        'bu hujjat tashqi tizimdan (sh5) keladi',
        code: 'mirror_owned',
        status: 409,
        details: {'source': 'sh5'},
      );
      final ui = coreErrorUz(e);
      expect(ui.title, 'SH5 dan ko\'chirilgan hujjat — SH5 da tuzatiladi');
      expect(ui.hint, contains('Nusxa'));
      expect(ui.warning, isTrue, reason: 'qizil emas — sariq');
    });

    test('409 mirror_owned (rk7) — kassa matni', () {
      final ui = coreErrorUz(const CoreApiException('…',
          code: 'mirror_owned', status: 409, details: {'source': 'rk7'}));
      expect(ui.title, 'Kassa sotuvi — tuzatilmaydi');
    });

    test('409 conflict — hujjat holati o\'zgargan', () {
      final ui = coreErrorUz(
          const CoreApiException('ledger: hujjat posted emas',
              code: 'conflict', status: 409));
      expect(ui.title, 'Hujjat holati o\'zgargan');
    });

    test('403 — qaysi ruxsat kerakligi aytiladi', () {
      final ui = coreErrorUz(const CoreApiException('ruxsat yo\'q',
          code: 'forbidden', status: 403, perm: 'doc.cancel'));
      expect(ui.title, 'Sizda bu amalga ruxsat yo\'q');
      expect(ui.hint, contains('Hujjatni bekor qilish'));
    });

    test('403 ombor cheklovi — ombor nomi bilan', () {
      final ui = coreErrorUz(
        const CoreApiException('bu omborga ruxsat yo\'q',
            code: 'forbidden', status: 403, details: {'sklad_id': 11}),
        skladName: (id) => 'Резка и Украшение',
      );
      expect(ui.title, contains('Резка и Украшение'));
    });

    test('422: to\'plamda «dan» va «ga» bir xil ombor', () {
      final ui = coreErrorUz(const CoreApiException(
          'docs[1]: from_sklad va to_sklad bir xil',
          code: 'validation',
          status: 422,
          details: {'index': 1}));
      expect(ui.title, '«Qayerdan» va «qayerga» bir xil ombor');
    });

    test('422 validation — batch indeksi tafsilotda ko\'rinadi', () {
      final ui = coreErrorUz(const CoreApiException('docs[1]: qatorlar bo\'sh',
          code: 'validation', status: 422, details: {'index': 1}));
      expect(ui.title, 'Ma\'lumot to\'liq emas');
      expect(ui.hint, contains('index: 1'));
    });

    test('422 insufficient — strict omborda qoldiq yetmadi', () {
      final ui = coreErrorUz(const CoreApiException(
          'ledger: qoldiq yetarli emas (strict ombor)',
          code: 'insufficient',
          status: 422,
          details: {'index': 2}));
      expect(ui.title, 'Qoldiq yetmaydi');
      expect(ui.hint, contains('strict ombor'));
    });

    test('eski server (404/405/501) — «Server yangilanmagan»', () {
      expect(coreIsMissingEndpoint(const CoreApiException('', status: 404)),
          isTrue);
      expect(coreIsMissingEndpoint(const CoreApiException('', status: 405)),
          isTrue);
      expect(coreIsMissingEndpoint(const CoreApiException('', status: 501)),
          isTrue);
      expect(coreIsMissingEndpoint(const CoreApiException('', status: 409)),
          isFalse);
      expect(kCoreOldServerMsg, 'Server yangilanmagan — administratorga ayting');
    });
  });

  group('Yangi JSON maydonlari', () {
    test('rework javobi: reworked_from + from_number + external_id', () {
      final d = CoreDoc.fromJson(const {
        'id': 7071,
        'type': 'transfer',
        'status': 'draft',
        'doc_date': '2026-09-21',
        'comment': '[tuzatish №ПМ-002304]',
        'source': 'app',
        'external_id': 'tuzatish:7070',
        'created_by_name': 'Admin',
        'reworked_from': 7070,
        'from_number': 'ПМ-002304',
      });
      expect(d.isRework, isTrue);
      expect(d.reworkSourceId, 7070);
      expect(d.createdByName, 'Admin');
      expect(d.fromNumber, 'ПМ-002304');
    });

    test('external_id dan ham tuzatish aniqlanadi (ro\'yxat qatori)', () {
      final d = CoreDoc.fromJson(const {
        'type': 'transfer',
        'doc_date': '2026-09-21',
        'external_id': 'tuzatish:7070',
      });
      expect(d.isRework, isTrue);
      expect(d.reworkSourceId, 7070);
    });

    test('oddiy hujjat — tuzatish emas, ism bo\'sh', () {
      final d = CoreDoc.fromJson(const {
        'type': 'receipt',
        'doc_date': '2026-09-21',
        'source': 'sh5',
      });
      expect(d.isRework, isFalse);
      expect(d.reworkSourceId, isNull);
      expect(d.createdByName, isEmpty);
    });

    test('copy javobi: copied_from', () {
      final d = CoreDoc.fromJson(const {
        'type': 'transfer',
        'doc_date': '2026-09-21',
        'copied_from': 7031,
        'from_number': '364303',
      });
      expect(d.copiedFrom, 7031);
      expect(d.isRework, isFalse);
    });

    test('quick-batch javobi: docs + warnings.doc_index + existing', () {
      final r = CoreDocBatchResult.fromJson(const {
        'docs': [
          {
            'id': 7072,
            'type': 'transfer',
            'number': 'ПМ-002306',
            'to_sklad': 5,
            'status': 'posted',
            'doc_date': '2026-09-21',
            'total': 72853,
            'lines': [
              {'good_id': 10479, 'qty': 12000, 'unit': 'pcs'}
            ],
          },
          {
            'id': 7073,
            'type': 'transfer',
            'number': 'ПМ-002307',
            'to_sklad': 18,
            'status': 'posted',
            'doc_date': '2026-09-21',
            'total': 33207,
            'lines': [],
          },
        ],
        'existing': [1],
        'warnings': [
          {
            'code': 'negative_stock',
            'sklad_id': 11,
            'good_id': 10479,
            'qty': -12000,
            'msg': 'partiya yetmadi',
            'doc_index': 0,
          },
          {'code': 'rounding', 'msg': 'yaxlitlash', 'doc_index': -1},
        ],
      });
      expect(r.docs.length, 2);
      expect(r.docs.first.number, 'ПМ-002306');
      expect(r.total, 72853 + 33207);
      expect(r.existing, [1]);
      expect(r.warnings.first.docIndex, 0);
      expect(r.warnings.last.docIndex, -1);
      // Kod bo'yicha guruhlash natija ekranidagidek ishlaydi.
      final groups = coreGroupWarnings(r.warnings);
      expect(groups.keys.first, 'negative_stock');
      expect(groups.length, 2);
    });

    test('eski javobda doc_index yo\'q — −1', () {
      final w = CoreDocWarning.fromJson(const {'code': 'no_batch'});
      expect(w.docIndex, -1);
    });
  });
}
