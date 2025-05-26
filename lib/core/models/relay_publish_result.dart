/// Result of publishing an event to relays
class RelayPublishResult {
  final String eventId;
  final Map<String, bool> relayResults;
  final int successCount;
  final int totalRelays;
  
  RelayPublishResult({
    required this.eventId,
    required this.relayResults,
  }) : successCount = relayResults.values.where((v) => v).length,
       totalRelays = relayResults.length;
  
  bool get isSuccess => successCount >= 2; // At least 2 relays
  
  double get successRate => totalRelays > 0 ? successCount / totalRelays : 0.0;
  
  List<String> get successfulRelays => relayResults.entries
      .where((e) => e.value)
      .map((e) => e.key)
      .toList();
  
  List<String> get failedRelays => relayResults.entries
      .where((e) => !e.value)
      .map((e) => e.key)
      .toList();
}