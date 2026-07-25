Map<String, dynamic> normalizeFirebaseMap(Map<dynamic, dynamic> map) {
  final result = <String, dynamic>{};
  map.forEach((key, value) {
    if (value is Map) {
      result[key.toString()] = normalizeFirebaseMap(value);
    } else {
      result[key.toString()] = value;
    }
  });
  return result;
}

double parseFirebaseDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}
