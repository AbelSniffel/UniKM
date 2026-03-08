/// Shared formatting utilities
library;

/// Format a byte count as a human-readable string (e.g. '1.5 MB').
/// 
/// Returns 'Unknown size' if [bytes] is null.
String formatFileSize(int? bytes) {
  if (bytes == null) return 'Unknown size';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
