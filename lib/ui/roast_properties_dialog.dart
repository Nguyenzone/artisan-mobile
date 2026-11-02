import 'package:flutter/material.dart';

import '../models/roast_profile.dart';

/// Hộp thoại "Roast Properties": tên mẻ, loại hạt, khối lượng, ghi chú.
/// Trả về true nếu người dùng bấm nút đồng ý (dữ liệu đã được ghi vào [p]).
Future<bool> showRoastPropertiesDialog(
  BuildContext context,
  RoastProfile p, {
  String title = 'Thuộc tính mẻ rang',
  String okLabel = 'OK',
  String cancelLabel = 'Huỷ',
}) async {
  final titleCtl = TextEditingController(text: p.title);
  final beansCtl = TextEditingController(text: p.beans);
  String fmtW(double v) => v == 0 ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());
  final inCtl = TextEditingController(text: fmtW(p.weightIn));
  final outCtl = TextEditingController(text: fmtW(p.weightOut));
  final notesCtl = TextEditingController(text: p.roastingNotes);
  final cupCtl = TextEditingController(text: p.cuppingNotes);

  double parse(String s) => double.tryParse(s.trim().replaceAll(',', '.')) ?? 0;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setState) {
        final wi = parse(inCtl.text);
        final wo = parse(outCtl.text);
        final loss = (wi > 0 && wo > 0) ? (wi - wo) / wi * 100 : null;
        final ph = p.phases();
        return AlertDialog(
          title: Text(title),
          scrollable: true,
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: titleCtl,
                  decoration: const InputDecoration(labelText: 'Tên mẻ rang (Title)', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: beansCtl,
                  decoration: const InputDecoration(labelText: 'Loại hạt (Beans)', isDense: true),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: inCtl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: 'KL hạt xanh (${p.weightUnit})', isDense: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: outCtl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: 'KL sau rang (${p.weightUnit})', isDense: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                if (loss != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Hao hụt: ${loss.toStringAsFixed(1)} %', style: const TextStyle(color: Colors.black54)),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesCtl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Ghi chú rang', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cupCtl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Ghi chú cupping', isDense: true),
                ),
                if (p.hasCharge) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Sấy: ${fmtTime(ph.drying)}   Maillard: ${fmtTime(ph.maillard)}   '
                    'Phát triển: ${fmtTime(ph.development)}   Tổng: ${fmtTime(ph.total)}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancelLabel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(okLabel)),
          ],
        );
      });
    },
  );

  if (ok == true) {
    p.title = titleCtl.text.trim();
    p.beans = beansCtl.text.trim();
    p.weightIn = parse(inCtl.text);
    p.weightOut = parse(outCtl.text);
    p.roastingNotes = notesCtl.text;
    p.cuppingNotes = cupCtl.text;
  }
  // Không dispose controller ngay: hộp thoại vẫn đang chạy hiệu ứng đóng.
  return ok == true;
}
