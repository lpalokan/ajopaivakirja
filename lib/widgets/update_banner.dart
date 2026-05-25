import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import '../providers/update_check_provider.dart';

/// Renders a thin banner on the home screen when the most recent
/// [updateCheckProvider] result is a non-null [UpdateInfo]. While
/// loading, errored, or known up-to-date the widget collapses to
/// `SizedBox.shrink()` so it stays out of the way until there's
/// something to say.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateCheckProvider);
    // `state.value` re-throws on AsyncError (Riverpod 2 behaviour);
    // `valueOrNull` collapses both loading and error to null so the
    // banner stays hidden when the manifest is unreachable.
    final info = state.valueOrNull;
    if (info == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        color: theme.colorScheme.primaryContainer,
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(
            Symbols.system_update,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          title: Text(
            'Päivitys saatavilla',
            style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
          ),
          subtitle: Text(
            'v${info.version} (build ${info.buildNumber})',
            style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
          ),
          trailing: FilledButton(
            onPressed: () => ref.read(updateCheckProvider.notifier).install(),
            child: const Text('Asenna'),
          ),
        ),
      ),
    );
  }
}
