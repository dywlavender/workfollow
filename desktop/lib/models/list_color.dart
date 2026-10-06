/// The shared 14-colour list palette. Values are ARGB integers so the model
/// stays independent from Flutter while views can pass them to `Color`.
///
/// **Keep in sync with the macOS side:** `WFListPalette.argb` in
/// `macos-native/WorkFollow/Application/TaskListProjection.swift`. The two
/// tables are the same contract, slot for slot; changing one without the other
/// makes the same list render in two different colours on the two platforms.
///
/// Slots 0…10 were re-saturated on 2026-10-06 (parenthesised values are the
/// originals). The macOS calendar drew its task bars as `base.opacity(0.36)`
/// over a near-white grid (measured rgb(242,244,248)), so ~64% of every bar was
/// background and the palette read as washed-out pastel. On white, "lighter"
/// and "more saturated" move in opposite directions, so the fix was to raise
/// the base saturation in HSL (S x 1.55, L untouched) rather than to touch the
/// alpha — lightness on screen barely moves, chroma gains ~45%.
///
/// Slots 11…13 are the achromatic ones and were deliberately left alone; they
/// are only reachable through an explicit colour choice.
const List<int> listColorPalette = <int>[
  0xFFFF4153, // red      (was 0xFFE35D6A)
  0xFFFF7228, // orange   (was 0xFFE8793F)
  0xFFFFB703, // yellow   (was 0xFFD7A62B)
  0xFFB1C41C, // olive    (was 0xFF9AA63A)
  0xFF27C264, // green    (was 0xFF42A66A)
  0xFF19C7B6, // mint     (was 0xFF38A89D)
  0xFF0AB8DA, // cyan     (was 0xFF2F9FB5)
  0xFF1A82FC, // blue     (was 0xFF4285D4)
  0xFF394DE7, // indigo   (was 0xFF5865C8)
  0xFF7837E6, // purple   (was 0xFF8056C7)
  0xFFE02DA5, // magenta  (was 0xFFC04D9A)
  0xFF9A756A, // warm grey  -- achromatic, unchanged
  0xFF66758A, // slate      -- achromatic, unchanged
  0xFF8A909B, // grey       -- achromatic, unchanged
];

/// Parses #RRGGBB or #AARRGGBB values from a migration record.
int? colorValueFromHex(String? raw) {
  if (raw == null) return null;
  var value = raw.trim();
  if (value.startsWith('#')) value = value.substring(1);
  if (value.startsWith('0x') || value.startsWith('0X')) {
    value = value.substring(2);
  }
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8 || int.tryParse(value, radix: 16) == null) return null;
  return int.parse(value, radix: 16);
}

String colorHexFromValue(int value) {
  final rgb = value & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Gives a stable default without storing a derived value in every old
/// snapshot. This is intentionally a small character fold so equal list names
/// always receive the same swatch.
int listColorValueForName(String name, {String? override}) {
  final explicit = colorValueFromHex(override);
  if (explicit != null) return explicit;
  if (name.trim().isEmpty) return listColorPalette.first;
  var score = 0;
  for (final rune in name.runes) {
    score = (score + rune) & 0x7fffffff;
  }
  return listColorPalette[score % listColorPalette.length];
}
