import 'package:flutter/material.dart';

Future<T?> openPage<T>(BuildContext context, Widget page, {String? name}) =>
    Navigator.of(context).push<T>(MaterialPageRoute(
        settings: RouteSettings(name: name), builder: (_) => page));

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(error.toString())));
}

class WorkflowPage extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  const WorkflowPage(
      {super.key, required this.title, required this.children, this.actions});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  for (final child in children)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: child),
                ]))),
      );
}

class LoadView<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(T) builder;
  final VoidCallback retry;
  const LoadView(
      {super.key,
      required this.future,
      required this.builder,
      required this.retry});
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Column(children: [
            Text('Could not load data: ${snapshot.error}'),
            TextButton(onPressed: retry, child: const Text('Retry'))
          ]);
        }
        return builder(snapshot.data as T);
      });
}

class ActionTile extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  const ActionTile(this.title, this.subtitle, this.icon, this.onTap,
      {super.key});
  @override
  Widget build(BuildContext context) => Card(
      child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap));
}

Future<List<String>?> inputDialog(
    BuildContext context, String title, List<String> labels,
    {List<String>? initial}) async {
  final controllers = List.generate(
      labels.length, (i) => TextEditingController(text: initial?[i] ?? ''));
  final form = GlobalKey<FormState>();
  final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
              title: Text(title),
              content: SizedBox(
                  width: 440,
                  child: Form(
                      key: form,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        for (var i = 0; i < labels.length; i++)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextFormField(
                                  controller: controllers[i],
                                  decoration:
                                      InputDecoration(labelText: labels[i]),
                                  validator: (s) =>
                                      s == null || s.trim().isEmpty
                                          ? 'Required'
                                          : null)),
                      ])))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () {
                      if (form.currentState!.validate()) {
                        Navigator.pop(ctx,
                            controllers.map((c) => c.text.trim()).toList());
                      }
                    },
                    child: const Text('Continue'))
              ]));
  // Dialog transition may still be using the fields when its future resolves.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  for (final controller in controllers) {
    controller.dispose();
  }
  return result;
}
