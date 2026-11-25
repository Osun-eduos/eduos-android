import 'package:flutter/material.dart';

// Indigo and ochre, matching the EduOS web app.
const indigo = Color(0xFF2B3786);
const ochre = Color(0xFFB4651B);
const good = Color(0xFF1E7A4C);
const warn = Color(0xFF9A6408);
const bad = Color(0xFFB3261E);

ThemeData eduosTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: indigo, brightness: b, primary: b == Brightness.light ? indigo : const Color(0xFF8D9AF2), secondary: ochre);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    cardTheme: CardThemeData(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.outlineVariant))),
  );
}

Color statusColor(String s) => switch (s) {
      'PRESENT' || 'APPROVED' => good,
      'LATE' || 'SUBMITTED' || 'DRAFT' => warn,
      'ABSENT' || 'RETURNED' => bad,
      'EXCUSED' => indigo,
      _ => Colors.grey,
    };

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
      );
}
