import 'package:flutter/material.dart';

/// Champ de saisie compatible télécommande (Google TV / Android TV).
/// Sélection (OK) -> ouvre une boîte de dialogue avec le clavier.
class TvField extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String> onChanged;

  const TvField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.obscure = false,
    this.keyboardType,
  });

  Future<void> _edit(BuildContext context) async {
    final c = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: c,
          autofocus: true,
          obscureText: obscure,
          keyboardType: keyboardType,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('OK')),
        ],
      ),
    );
    c.dispose();
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final shown = value.isEmpty
        ? (hint ?? 'Appuyer pour saisir')
        : (obscure ? '•' * value.length : value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        onTap: () => _edit(context),
        tileColor: Colors.white10,
        focusColor: Colors.white24,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        subtitle: Text(
          shown,
          style: TextStyle(
              fontSize: 16,
              color: value.isEmpty ? Colors.white38 : Colors.white),
        ),
        trailing: const Icon(Icons.edit, size: 18),
      ),
    );
  }
}
