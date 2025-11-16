import 'package:flutter/material.dart';

/// Reusable loading overlay widget that blocks all user interactions
/// and shows a loading spinner with an optional message
class LoadingOverlay extends StatelessWidget {
  final String? message;
  final Color? backgroundColor;
  final Color? spinnerColor;

  const LoadingOverlay({
    Key? key,
    this.message,
    this.backgroundColor,
    this.spinnerColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor ?? Colors.black.withOpacity(0.5),
      child: Center(
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    spinnerColor ?? const Color(0xFF00588e),
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    message!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF00588e),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
