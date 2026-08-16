abstract class HistoryEvent {}

class LoadHistoryData extends HistoryEvent {
  final DateTime startDate;
  final DateTime endDate;
  final int? limit;

  LoadHistoryData({required this.startDate, required this.endDate, this.limit});
}

class FilterHistoryData extends HistoryEvent {
  final DateTime startDate;
  final DateTime endDate;
  final int? limit;

  FilterHistoryData({
    required this.startDate,
    required this.endDate,
    this.limit,
  });
}

class RefreshHistoryData extends HistoryEvent {}
