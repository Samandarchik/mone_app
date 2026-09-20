// core2/ui/reports/report_export.dart — hisobotni Excel (CSV) ga chiqarish.
// Server `?format=csv` bilan UTF-8 BOM li, `;` ajratgichli faylni beradi
// (Excel ikki marta bosishda to'g'ri ochadi). `Authorization` sarlavhasi
// kerak bo'lgani uchun brauzer havolasi EMAS — javob BAYT sifatida olinadi.
//
// Windows/desktop: foydalanuvchining «Downloads» papkasiga saqlanadi
// (`kamomad_2026-08-20_2026-09-19.csv`), so'ng «Ochish» / «Papkani ochish»
// taklif qilinadi (url_launcher). Android/iOS: vaqtinchalik faylga yozilib
// share_plus oynasi ochiladi. Ikkalasi ham ishlamasa — yo'l bufer xotiraga
// nusxalanadi (paketlar qo'shilmaydi: loyihada bor path_provider,
// share_plus, url_launcher ishlatiladi).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uz_ai_dev/core2/services/core_reports_service.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_logic.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

/// Hisobotni CSV qilib yuklab olish va saqlash/ulashish.
///
/// [path] — hisobot yo'li (`CoreReportPaths.*`), [query] — joriy filtrlar
/// (`format` servis o'zi qo'shadi), [fileKey] — fayl nomi boshi («kamomad»).
Future<void> coreExportCsv(
  BuildContext context, {
  required String path,
  required Map<String, dynamic> query,
  required String fileKey,
  String? from,
  String? to,
  String? suffix,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(
    content: Text('Excel (CSV) tayyorlanmoqda…'),
    duration: Duration(seconds: 2),
  ));
  CoreCsvData data;
  try {
    data = await CoreReportsService().csv(path, query);
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(coreReportErrorText(e)),
      backgroundColor: Colors.red.shade700,
      duration: const Duration(seconds: 5),
    ));
    return;
  }
  if (data.bytes.isEmpty) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(const SnackBar(content: Text('Fayl bo\'sh keldi')));
    return;
  }

  final name = coreCsvFileName(fileKey, from: from, to: to, suffix: suffix);
  final desktop = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  try {
    if (desktop) {
      final file = await _saveToDownloads(data.bytes, name);
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      await _savedDialog(context, file);
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(data.bytes, flush: true);
      messenger.hideCurrentSnackBar();
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv', name: name)],
        subject: name,
      ));
    }
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('Faylni saqlab bo\'lmadi: $e'),
      backgroundColor: Colors.red.shade700,
    ));
  }
}

/// «Downloads» papkasiga (bo'lmasa hujjatlar papkasiga) band bo'lmagan nom
/// bilan yozadi.
Future<File> _saveToDownloads(List<int> bytes, String name) async {
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {
    dir = null;
  }
  dir ??= await getApplicationDocumentsDirectory();
  var file = File('${dir.path}${Platform.pathSeparator}$name');
  for (var i = 2; await file.exists() && i < 50; i++) {
    file = File(
        '${dir.path}${Platform.pathSeparator}${coreCsvNameWithIndex(name, i)}');
  }
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<void> _savedDialog(BuildContext context, File file) async {
  final messenger = ScaffoldMessenger.of(context);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(children: [
        Icon(Icons.table_view, color: Colors.green),
        SizedBox(width: 8),
        Expanded(child: Text('Excel fayli saqlandi')),
      ]),
      content: SelectableText(file.path, style: const TextStyle(fontSize: 12.5)),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await _open(messenger, file.parent.path, file.path);
          },
          child: const Text('Papkani ochish'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await _open(messenger, file.path, file.path);
          },
          child: const Text('Ochish'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx),
          style: ElevatedButton.styleFrom(
              backgroundColor: kCoreAccent, foregroundColor: Colors.white),
          child: const Text('Yopish'),
        ),
      ],
    ),
  );
}

/// Faylni/papkani tizim dasturida ochish; bo'lmasa yo'lni buferga nusxalaydi.
Future<void> _open(
    ScaffoldMessengerState messenger, String target, String filePath) async {
  var ok = false;
  try {
    final uri = FileSystemEntity.isDirectorySync(target)
        ? Uri.directory(target)
        : Uri.file(target);
    ok = await launchUrl(uri);
  } catch (_) {
    ok = false;
  }
  if (!ok) {
    await Clipboard.setData(ClipboardData(text: filePath));
    messenger.showSnackBar(const SnackBar(
      content: Text('Ochib bo\'lmadi — fayl yo\'li nusxalandi'),
    ));
  }
}
