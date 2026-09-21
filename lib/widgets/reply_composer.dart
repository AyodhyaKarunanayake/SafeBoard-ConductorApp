import 'package:flutter/material.dart';

/// One-tap replies for the conductor. Tapping one fills the box so it can be
/// sent as is or edited first.
const List<String> kQuickReplies = [
  'On my way',
  'Please wait a moment',
  'I will arrange a seat change',
  'We reach your stop shortly',
];

/// The reply box shared by the message pop-up and the Messages page: quick
/// replies, a text field and a Send button. [onSend] returns null on success or
/// an error message, which is shown under the box without losing the text.
class ReplyComposer extends StatefulWidget {
  const ReplyComposer({super.key, required this.onSend, this.onSent});

  final Future<String?> Function(String text) onSend;

  /// Called after a reply was sent successfully (e.g. to close the pop-up).
  final VoidCallback? onSent;

  @override
  State<ReplyComposer> createState() => _ReplyComposerState();
}

class _ReplyComposerState extends State<ReplyComposer> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    final error = await widget.onSend(_controller.text);
    if (!mounted) return;
    if (error == null) {
      widget.onSent?.call();
      setState(() => _sending = false);
      _controller.clear();
    } else {
      setState(() {
        _sending = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final reply in kQuickReplies)
              ActionChip(
                label: Text(reply),
                onPressed: _sending
                    ? null
                    : () => setState(() {
                          _controller.text = reply;
                          _controller.selection =
                              TextSelection.collapsed(offset: reply.length);
                        }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('reply-field'),
          controller: _controller,
          enabled: !_sending,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Type a reply'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded, size: 18),
          label: const Text('Send reply'),
        ),
      ],
    );
  }
}
