import 'package:flutter/material.dart';

import '../services/supabase_service.dart';

/// Bottom-sheet modal for rating and reviewing a provider after a completed
/// booking session.
///
/// Usage:
/// ```dart
/// ReviewModal.show(context, bookingId: '...', providerId: '...', providerName: '...');
/// ```
class ReviewModal extends StatefulWidget {
  const ReviewModal({
    super.key,
    required this.bookingId,
    required this.providerId,
    required this.providerName,
    this.onReviewSubmitted,
  });

  final String bookingId;
  final String providerId;
  final String providerName;
  final VoidCallback? onReviewSubmitted;

  /// Convenience method that shows the bottom sheet and returns `true` when
  /// the review is submitted, or `false` / `null` when dismissed.
  static Future<bool> show(
    BuildContext context, {
    required String bookingId,
    required String providerId,
    required String providerName,
    VoidCallback? onReviewSubmitted,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFAF7F3),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ReviewModal(
        bookingId: bookingId,
        providerId: providerId,
        providerName: providerName,
        onReviewSubmitted: onReviewSubmitted,
      ),
    );
    return result ?? false;
  }

  @override
  State<ReviewModal> createState() => _ReviewModalState();
}

class _ReviewModalState extends State<ReviewModal> {
  int _rating = 0;
  final _commentController = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  String get _ratingLabel {
    switch (_rating) {
      case 1:
        return 'Poor / Mauvais';
      case 2:
        return 'Fair / Passable';
      case 3:
        return 'Good / Bien';
      case 4:
        return 'Very Good / Très Bien';
      case 5:
        return 'Excellent!';
      default:
        return 'Tap a star / Appuyez sur une étoile';
    }
  }

  Color get _ratingColor {
    if (_rating >= 4) return const Color(0xFF3FBF7F);
    if (_rating == 3) return const Color(0xFFFFB93F);
    if (_rating > 0) return const Color(0xFFF4665C);
    return Colors.grey;
  }

  Future<void> _submit() async {
    if (_rating == 0 || _submitting) return;

    setState(() => _submitting = true);

    try {
      await SupabaseService.instance.submitReview(
        bookingId: widget.bookingId,
        providerId: widget.providerId,
        rating: _rating,
        comment: _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        _submitted = true;
        _submitting = false;
      });

      // Brief delay so the user sees the success state.
      await Future.delayed(const Duration(milliseconds: 800));

      if (!mounted) return;
      Navigator.of(context).pop(true);
      widget.onReviewSubmitted?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Thank you for your review! / Merci pour votre avis!'),
          backgroundColor: Color(0xFF3FBF7F),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not submit review: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    if (_submitted) {
      return _buildSuccessState();
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 18 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar.
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0x22000000),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title.
          const Text(
            'Rate Your Experience',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'How was your session with ${widget.providerName}?',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),

          // 5-Star selector.
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (index) {
                final star = index + 1;
                final filled = star <= _rating;
                return GestureDetector(
                  onTap: () => setState(() => _rating = star),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: AnimatedScale(
                      scale: filled ? 1.15 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        filled ? Icons.star_rounded : Icons.star_border_rounded,
                        size: 42,
                        color: filled
                            ? const Color(0xFFFFB93F)
                            : Colors.grey.shade300,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),

          // Rating label.
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _ratingLabel,
                key: ValueKey<int>(_rating),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _ratingColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Comment field.
          TextField(
            controller: _commentController,
            maxLines: 3,
            maxLength: 300,
            decoration: InputDecoration(
              hintText: 'Leave a comment for your stylist...',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 20),

          // Submit button.
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _rating == 0 || _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF4665C),
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Submit Review / Soumettre',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Success checkmark.
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0x1A3FBF7F),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 40,
              color: Color(0xFF3FBF7F),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Thank You!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your review helps other clients find the best stylists.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
