/// Read-only diagnostics returned by [LocalAppStore] maintenance calls.
///
/// These are *reports*, not control surfaces: the store never mutates a
/// report after returning it, and callers (UI/debug tooling) can render
/// them verbatim. All lists/maps are defensive copies so a report stays
/// stable even as the store keeps running.
library;

/// Outcome of [LocalAppStore.migrate].
///
/// [scanned]/[upgraded] are keyed by box name. [refused] holds
/// `"<box>/<key>"` descriptors for envelopes whose writer version is newer
/// than (or not parseable as) [storageSchemaVersion] — those payloads are
/// deliberately *not* reinterpreted. [corrupt] holds descriptors for entries
/// that were not maps at all and therefore could not be migrated.
class MigrationReport {
  /// Creates an empty report.
  MigrationReport();

  /// Envelopes inspected per box.
  final Map<String, int> scanned = <String, int>{};

  /// Envelopes rewritten in canonical form per box.
  final Map<String, int> upgraded = <String, int>{};

  /// `"<box>/<key>"` entries whose version is newer/unknown; left untouched.
  final List<String> refused = <String>[];

  /// `"<box>/<key>"` entries that were not maps; left untouched.
  final List<String> corrupt = <String>[];

  /// True when every scanned envelope was already current (nothing to do).
  bool get isClean => refused.isEmpty && corrupt.isEmpty;

  /// Total envelopes rewritten.
  int get upgradedCount =>
      upgraded.values.fold<int>(0, (sum, value) => sum + value);

  @override
  String toString() {
    if (isClean && upgradedCount == 0) {
      return 'MigrationReport(clean, scanned=$scanned)';
    }
    return 'MigrationReport(upgraded=$upgraded, refused=$refused, '
        'corrupt=$corrupt)';
  }
}

/// Snapshot of storage integrity: quarantined boxes + skipped entries.
///
/// [quarantinedBoxes] names boxes that failed to open and were moved aside
/// (never deleted) so [LocalAppStore.init] could continue with the rest.
/// [corruptEntries] maps a box name to the keys that were skipped while
/// listing/reading because they did not fit the expected envelope shape.
class IntegrityReport {
  /// Creates a report from defensive copies of [quarantinedBoxes] and
  /// [corruptEntries].
  IntegrityReport({
    Iterable<String> quarantinedBoxes = const <String>[],
    Map<String, Iterable<String>> corruptEntries =
        const <String, Iterable<String>>{},
  }) : quarantinedBoxes = List<String>.unmodifiable(
         (quarantinedBoxes.toList()..sort()),
       ),
       corruptEntries = Map<String, List<String>>.unmodifiable(
         <String, List<String>>{
           for (final entry in corruptEntries.entries)
             entry.key: List<String>.unmodifiable(entry.value.toList()..sort()),
         },
       );

  /// Boxes that were quarantined (moved aside) because `openBox` threw.
  final List<String> quarantinedBoxes;

  /// Box name -> keys skipped while reading (not maps / failed to parse).
  final Map<String, List<String>> corruptEntries;

  /// Total skipped entries across all boxes.
  int get corruptEntryCount =>
      corruptEntries.values.fold<int>(0, (sum, keys) => sum + keys.length);

  /// Number of boxes quarantined at open.
  int get quarantinedBoxCount => quarantinedBoxes.length;

  /// True when nothing was quarantined and no entry was skipped.
  bool get isClean => quarantinedBoxes.isEmpty && corruptEntryCount == 0;

  @override
  String toString() =>
      'IntegrityReport(quarantined=$quarantinedBoxes, '
      'corrupt=$corruptEntries)';
}
