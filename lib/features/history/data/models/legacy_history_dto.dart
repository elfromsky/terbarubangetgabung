class LegacyHistoryDto {
  final String id;
  final dynamic timestamp;
  final dynamic mcb1;
  final dynamic dht;

  const LegacyHistoryDto({
    required this.id,
    required this.timestamp,
    this.mcb1,
    this.dht,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'mcb1': mcb1,
      if (dht != null) 'dht': dht,
    };
  }
}
