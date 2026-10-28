import 'package:flutter/material.dart';

/// The lowercase words of a settings search.
List<String> searchWords(String query) => query
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .where((word) => word.isNotEmpty)
    .toList(growable: false);

/// Whether [text] contains every word of [query], in any order.
bool settingsSearchMatches(String query, String text) {
  final lower = text.toLowerCase();
  return searchWords(query).every(lower.contains);
}

/// [text] in [style], with every word of [query] marked in [highlight].
TextSpan searchHighlightSpan(
  String text,
  String query,
  TextStyle style,
  TextStyle highlight,
) {
  final lower = text.toLowerCase();
  final words = searchWords(query);
  // Case folding that changes the length would misplace the marks.
  if (words.isEmpty || lower.length != text.length) {
    return TextSpan(text: text, style: style);
  }
  final marked = List.filled(text.length, false);
  for (final word in words) {
    for (var i = lower.indexOf(word); i >= 0; i = lower.indexOf(word, i + 1)) {
      marked.fillRange(i, i + word.length, true);
    }
  }
  final spans = <TextSpan>[];
  var start = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i < text.length && marked[i] == marked[start]) continue;
    spans.add(
      TextSpan(
        text: text.substring(start, i),
        style: marked[start] ? highlight : null,
      ),
    );
    start = i;
  }
  return TextSpan(style: style, children: spans);
}

/// Marks a searched word: a strong [accent] tint behind the text.
TextStyle searchMarkStyle(Color accent) =>
    TextStyle(backgroundColor: accent.withValues(alpha: 0.35));

/// The settings search, for the settings cards below it to mark a match.
class SettingsSearchScope extends InheritedWidget {
  const SettingsSearchScope({
    super.key,
    required this.query,
    required super.child,
  });

  final String query;

  /// The search, or empty outside the settings page.
  static String queryOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SettingsSearchScope>()
          ?.query ??
      '';

  @override
  bool updateShouldNotify(SettingsSearchScope oldWidget) =>
      query != oldWidget.query;
}

/// Fades a settings search match in, holds it while it matches, and fades
/// it out without unmounting it.
class SearchHighlight extends StatefulWidget {
  const SearchHighlight({
    super.key,
    required this.query,
    required this.isMatch,
    required this.builder,
  });

  final String query;
  final bool isMatch;
  final Widget Function(BuildContext context, double value) builder;

  @override
  State<SearchHighlight> createState() => _SearchHighlightState();
}

class _SearchHighlightState extends State<SearchHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: _matches ? 1 : 0,
  );

  bool get _matches => widget.isMatch && widget.query.trim().isNotEmpty;

  @override
  void didUpdateWidget(covariant SearchHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.animateTo(_matches ? 1 : 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => widget.builder(
      context,
      Curves.easeOutCubic.transform(_controller.value),
    ),
  );
}
