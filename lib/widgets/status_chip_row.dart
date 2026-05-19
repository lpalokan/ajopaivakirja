import 'package:flutter/material.dart';

/// Horizontal chip row for key status indicators at the top of History.
///
/// Renders when its condition is true:
/// - drafts (amber, "{n} luonnosta odottaa")
/// - unsynced (yellow, "{n} synkronoimatta")
/// - monthComplete (green, "{monthName} valmis")
class StatusChipRow extends StatelessWidget {
  final int draftCount;
  final int unsyncedCount;
  final String? completeMonthName;
  final VoidCallback? onDraftsTap;
  final VoidCallback? onUnsyncedTap;

  const StatusChipRow({
    super.key,
    this.draftCount = 0,
    this.unsyncedCount = 0,
    this.completeMonthName,
    this.onDraftsTap,
    this.onUnsyncedTap,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (draftCount > 0) {
      chips.add(ActionChip(
        avatar: const Icon(Icons.edit_note, size: 18, color: Colors.amber),
        label: Text('$draftCount luonnosta odottaa'),
        backgroundColor: Colors.amber.shade50,
        side: const BorderSide(color: Colors.amber),
        onPressed: onDraftsTap,
      ));
    }

    if (unsyncedCount > 0) {
      chips.add(ActionChip(
        avatar: const Icon(Icons.cloud_upload_outlined, size: 18),
        label: Text('$unsyncedCount synkronoimatta'),
        backgroundColor: Colors.yellow.shade50,
        side: BorderSide(color: Colors.yellow.shade700),
        onPressed: onUnsyncedTap,
      ));
    }

    if (completeMonthName != null) {
      chips.add(Chip(
        avatar: const Icon(Icons.check_circle, size: 18, color: Colors.green),
        label: Text('$completeMonthName valmis'),
        backgroundColor: Colors.green.shade50,
        side: const BorderSide(color: Colors.green),
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: chips,
      ),
    );
  }
}
