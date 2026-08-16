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

int? parseFirebaseEpochSeconds(dynamic value) {
  if (value is int) return value >= 0 ? value : null;
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    final seconds = value.toInt();
    return seconds >= 0 ? seconds : null;
  }
  if (value is String) {
    final seconds = int.tryParse(value.trim());
    return seconds != null && seconds >= 0 ? seconds : null;
  }
  return null;
}
