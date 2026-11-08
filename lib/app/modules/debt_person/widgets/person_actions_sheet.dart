import 'package:flutter/material.dart';

/// Rename field plus "delete person". [onRename] returns an error message to
/// show inline, or null on success. [onDelete] asks for confirmation itself.
class PersonActionsSheet extends StatefulWidget {
  const PersonActionsSheet({
    super.key,
    required this.name,
    required this.onRename,
    required this.onDelete,
  });

  final String name;
  final Future<String?> Function(String name) onRename;
  final Future<void> Function() onDelete;

  @override
  State<PersonActionsSheet> createState() => _PersonActionsSheetState();
}

class _PersonActionsSheetState extends State<PersonActionsSheet> {
  late final _name = TextEditingController(text: widget.name);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await widget.onRename(_name.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _error = error;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(labelText: 'الاسم', errorText: _error),
            ),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: _busy ? null : _submit, child: const Text('حفظ')),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _busy ? null : widget.onDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('حذف الشخص'),
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      ),
    );
  }
}
