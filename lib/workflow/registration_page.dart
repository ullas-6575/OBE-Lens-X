import 'package:flutter/material.dart';

import 'models.dart';
import 'repository.dart';
import 'ui.dart';

/// Administrators review registrations here: approve or reject each account.
class RegistrationsPage extends StatefulWidget {
  final WorkflowRepository repository;
  const RegistrationsPage({super.key, required this.repository});
  @override
  State<RegistrationsPage> createState() => _RegistrationsPageState();
}

class _RegistrationsPageState extends State<RegistrationsPage> {
  late Future<List<Json>> _accounts = widget.repository.accounts();
  String? _busyId;

  void _reload() => setState(() {
        _accounts = widget.repository.accounts();
      });

  String _name(Json account) {
    final name = (account['full_name'] as String? ?? '').trim();
    return name.isEmpty ? 'Unnamed account' : name;
  }

  Future<void> _decide(Json account, RegistrationStatus status) async {
    if (status == RegistrationStatus.rejected) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                  title: const Text('Reject registration?'),
                  content: Text(
                      '${_name(account)} will be blocked until an administrator approves them.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Reject')),
                  ]));
      if (confirmed != true || !mounted) return;
    }

    final id = account['id'] as String;
    setState(() => _busyId = id);
    try {
      await widget.repository.setRegistrationStatus(id, status);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(status == RegistrationStatus.approved
              ? '${_name(account)} approved.'
              : '${_name(account)} rejected.')));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WorkflowPage(
      title: 'Registrations',
      actions: [
        IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh))
      ],
      children: [
        LoadView(
            future: _accounts,
            retry: _reload,
            builder: (accounts) {
              final pending = accounts
                  .where((account) =>
                      RegistrationStatus.of(account) ==
                      RegistrationStatus.pending)
                  .toList();
              final reviewed = accounts
                  .where((account) =>
                      RegistrationStatus.of(account) !=
                      RegistrationStatus.pending)
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Pending (${pending.length})',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (pending.isEmpty)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No registrations are waiting for review.')),
                  for (final account in pending) _pendingCard(account),
                  if (reviewed.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Reviewed', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final account in reviewed) _reviewedTile(account),
                  ],
                ],
              );
            })
      ],
    );
  }

  Widget _pendingCard(Json account) {
    final theme = Theme.of(context);
    final busy = _busyId == account['id'];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person_outline)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_name(account), style: theme.textTheme.titleMedium),
                      Text(account['email'] as String? ?? '',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => _decide(account, RegistrationStatus.rejected),
                    child: const Text('Reject')),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: busy
                        ? null
                        : () => _decide(account, RegistrationStatus.approved),
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Approve')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewedTile(Json account) {
    final theme = Theme.of(context);
    final approved =
        RegistrationStatus.of(account) == RegistrationStatus.approved;
    final busy = _busyId == account['id'];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          approved ? Icons.check_circle_outline : Icons.block,
          color: approved ? theme.colorScheme.primary : theme.colorScheme.error,
        ),
        title: Text(_name(account)),
        subtitle: Text(account['email'] as String? ?? ''),
        trailing: TextButton(
          onPressed: busy
              ? null
              : () => _decide(
                  account,
                  approved
                      ? RegistrationStatus.rejected
                      : RegistrationStatus.approved),
          child: Text(approved ? 'Reject' : 'Approve'),
        ),
      ),
    );
  }
}
