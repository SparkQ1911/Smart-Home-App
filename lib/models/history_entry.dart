class HistoryEntry {
  const HistoryEntry({
    required this.title,
    required this.detail,
    required this.timestamp,
  });

  final String title;
  final String detail;
  final DateTime? timestamp;

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawTime = json['timestamp'] ??
        json['updatedAt'] ??
        json['createdAt'] ??
        json['created_at'];
    final timestamp =
        rawTime == null ? null : DateTime.tryParse(rawTime.toString());
    if (rawTime != null && timestamp == null) {
      throw const FormatException('Thời gian lịch sử không hợp lệ.');
    }
    return HistoryEntry(
      title: (json['deviceName'] ??
              json['device_name'] ??
              json['name'] ??
              'Sự kiện')
          .toString(),
      detail: (json['status'] ??
              json['state'] ??
              json['action'] ??
              json['type'] ??
              'Đã cập nhật')
          .toString(),
      timestamp: timestamp,
    );
  }
}
