import 'package:flutter/material.dart';

/// Asks for a person's name and pops with it. [onSubmit] returns an error
/// message to show inline, or null when the name was accepted.
class AddPersonDialog extends StatefulWidget {
  const AddPersonDialog({super.key, required this.onSubmit});

  final Future<String?> Function(String name) onSubmit;

  @override
  State<AddPersonDialog> createState() => _AddPersonDialogState();
}

class _AddPersonDialogState extends State<AddPersonDialog> {
  final _name = TextEditingController();
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
    final error = await widget.onSubmit(_name.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(_name.text.trim());
    } else {
      setState(() {
        _error = error;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة شخص'),
      content: TextField(
        controller: _name,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(labelText: 'الاسم', errorText: _error),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('إضافة')),
      ],
    );
  }
}
