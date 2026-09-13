/// The shared 14-colour list palette. Values are ARGB integers so the model
/// stays independent from Flutter while views can pass them to `Color`.
const List<int> listColorPalette = <int>[
  0xFFE35D6A, // red
  0xFFE8793F, // orange
  0xFFD7A62B, // yellow
  0xFF9AA63A, // olive
  0xFF42A66A, // green
  0xFF38A89D, // mint
  0xFF2F9FB5, // cyan
  0xFF4285D4, // blue
  0xFF5865C8, // indigo
  0xFF8056C7, // purple
  0xFFC04D9A, // magenta
  0xFF9A756A, // warm grey
  0xFF66758A, // slate
  0xFF8A909B, // grey
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
