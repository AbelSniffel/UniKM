import 'package:flutter/material.dart';

/// Shared by update status cards and their Dev Tools previews.
abstract final class UpdateStatusIcons {
  static const idle = Icons.pending_outlined;
  static const checking = Icons.refresh;
  static const upToDate = Icons.check_circle;
  static const available = Icons.new_releases;
  static const downloading = Icons.download;
  static const downloaded = Icons.download_done;
  static const error = Icons.error;
}
