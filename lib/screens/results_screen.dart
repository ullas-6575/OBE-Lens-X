import 'package:flutter/material.dart';
import '../services/result_service.dart';

class ResultsScreen extends StatefulWidget {
  final ResultService resultService;

  const ResultsScreen({
    super.key,
    this.resultService = const SupabaseResultService(),
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late Future<List<Map<String, dynamic>>> _results;

  @override
  void initState() {
    super.initState();
    _results = widget.resultService.fetchResults();
  }

  @override
  void didUpdateWidget(covariant ResultsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resultService != widget.resultService) {
      _results = widget.resultService.fetchResults();
    }
  }

  String _formatSavedAt(dynamic value) {
    if (value == null) {
      return 'Unknown';
    }
    try {
      final date = DateTime.parse(value.toString()).toLocal();
      return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Results'),
        centerTitle: true,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _results,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load results from the database.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final results = snapshot.data ?? const [];
          if (results.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No saved results found.'),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: results.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final result = results[index];
              final marks = result['marks'];
              final total = result['grand_total'] ?? 0;
              final tableType = result['table_type'] ?? 'N/A';
              final rollNo = result['roll_no'] ?? 'N/A';

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              rollNo,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(tableType),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Grand total: $total'),
                      const SizedBox(height: 8),
                      Text('Saved at: ${_formatSavedAt(result['created_at'])}'),
                      if (marks is Map) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Marks:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ...marks.entries.map((entry) {
                          final question = entry.key;
                          final rowMarks = entry.value;
                          if (rowMarks is Map) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                'Q$question: ${rowMarks.entries.map((e) => '${e.key}:${e.value}').join(', ')}',
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        }),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
