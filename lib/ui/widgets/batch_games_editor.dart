import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/batch_parser.dart';
import '../../core/constants/platform_patterns.dart';
import 'platform_icon.dart';

const _pillHorizontalPadding = 12.0;
const _dividerClearance = 8.0;
const _separatorExtraWidth = 2 * (_pillHorizontalPadding + _dividerClearance);
const _joinedSeparatorExtraWidth = 12.0;
const _platformGutter = 28.0;
const _platformIconSlotWidth = 26.0;

class _BatchLine {
  _BatchLine(this.text, this.offset) : parts = parseBatchLine(text);
  final String text;
  final int offset;
  final BatchLineParts? parts;
}

/// Styling preserves the original text, selection, composing range and undo.
class BatchGamesEditingController extends TextEditingController {
  Map<int, double> _rowMerges = {};

  void _updateRowMerges(Map<int, double> merges) {
    _rowMerges = merges;
    // Only the presentation changes; text, selection, composing and undo remain intact.
    notifyListeners();
  }

  String? _lastText;
  List<_BatchLine> _lines = [];

  List<_BatchLine> get _currentLines {
    if (_lastText != text) {
      var offset = 0;
      _lines = text.split('\n').map((line) {
        final result = _BatchLine(line, offset);
        offset += line.length + 1;
        return result;
      }).toList();
      _lastText = text;
    }
    return _lines;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final children = <TextSpan>[];
    final theme = Theme.of(context).extension<AppThemeData>();
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    void append(String text, int offset, TextStyle? partStyle) {
      final end = offset + text.length;
      if (composing.isValid &&
          composing.start < end &&
          composing.end > offset) {
        final start = math.max(0, composing.start - offset);
        final stop = math.min(text.length, composing.end - offset);
        children.add(
          TextSpan(text: text.substring(0, start), style: partStyle),
        );
        children.add(
          TextSpan(
            text: text.substring(start, stop),
            style: (partStyle ?? const TextStyle()).copyWith(
              decoration: TextDecoration.underline,
            ),
          ),
        );
        children.add(TextSpan(text: text.substring(stop), style: partStyle));
      } else {
        children.add(TextSpan(text: text, style: partStyle));
      }
    }

    final lines = _currentLines;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final parts = line.parts;
      if (parts == null) {
        append(line.text, line.offset, null);
      } else {
        append(line.text.substring(0, parts.titleEnd), line.offset, null);
        // The separator remains text for clipboard/undo, but its break is painted.
        final separator = line.text.substring(parts.titleEnd, parts.keyStart);
        append(
          separator,
          line.offset + parts.titleEnd,
          TextStyle(
            color: Colors.transparent,
            // Reserve padding around the break without changing clipboard text.
            // Additional typed spaces retain their own normal advance width.
            letterSpacing: separator.isEmpty
                ? null
                : (style?.letterSpacing ?? 0) +
                      ui.lerpDouble(
                            _separatorExtraWidth,
                            _joinedSeparatorExtraWidth,
                            _rowMerges[i] ?? 0,
                          )! /
                          separator.characters.length,
          ),
        );
        append(
          line.text.substring(parts.keyStart),
          line.offset + parts.keyStart,
          TextStyle(fontFamily: 'monospace', color: theme?.textSecondary),
        );
      }
      if (i < lines.length - 1) {
        append('\n', line.offset + line.text.length, null);
      }
    }
    return TextSpan(style: style, children: children);
  }
}

/// One native multiline editor with decorative, text-sized title/key pills.
/// Its visual divider introduces no separate field or pointer/keyboard target.
class BatchGamesEditor extends StatefulWidget {
  const BatchGamesEditor({
    super.key,
    required this.controller,
    required this.theme,
    required this.onChanged,
    this.platformOverride,
  });
  final BatchGamesEditingController controller;
  final AppThemeData theme;
  final ValueChanged<String> onChanged;

  /// Null detects each key; a selected platform overrides every row.
  final GamePlatform? platformOverride;

  @override
  State<BatchGamesEditor> createState() => _BatchGamesEditorState();
}

class _BatchGamesEditorState extends State<BatchGamesEditor>
    with SingleTickerProviderStateMixin {
  final _focus = FocusNode();
  final _horizontalScroll = ScrollController();
  final _surfaceKey = GlobalKey();
  final _viewportKey = GlobalKey();
  bool _revealScheduled = false;
  bool _hovered = false;
  late final AnimationController _animation;
  Map<int, double> _from = {};
  int? _active;
  late bool _inputWasEmpty;

  double _merge(int row) => ui.lerpDouble(
    _from[row] ?? 0,
    row == _active ? 1 : 0,
    Curves.easeInOutCubic.transform(_animation.value),
  )!;

  @override
  void initState() {
    super.initState();
    _inputWasEmpty = widget.controller.text.isEmpty;
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 1,
    );
    widget.controller._rowMerges = {};
    _animation.addListener(_syncRowMerges);
    _focus.addListener(_updateActiveRow);
    widget.controller.addListener(_updateActiveRow);
  }

  void _syncRowMerges() {
    widget.controller._updateRowMerges({
      for (var row = 0; row < widget.controller._currentLines.length; row++)
        row: _merge(row),
    });
    _scheduleRevealCaret();
  }

  @override
  void didUpdateWidget(covariant BatchGamesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_updateActiveRow);
      widget.controller.addListener(_updateActiveRow);
      _updateActiveRow();
      _syncRowMerges();
    }
  }

  void _updateActiveRow() {
    _scheduleRevealCaret();
    final selection = widget.controller.selection;
    final int? active = _focus.hasFocus && selection.isValid
        ? '\n'
              .allMatches(
                widget.controller.text.substring(
                  0,
                  selection.extentOffset.clamp(
                    0,
                    widget.controller.text.length,
                  ),
                ),
              )
              .length
        : null;
    final emptyChanged = _inputWasEmpty != widget.controller.text.isEmpty;
    _inputWasEmpty = widget.controller.text.isEmpty;
    if (active == _active) {
      if (emptyChanged) setState(() {});
      return;
    }
    _from = {
      for (var i = 0; i < widget.controller._currentLines.length; i++)
        if (_merge(i) > 0) i: _merge(i),
    };
    setState(() => _active = active);
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 1;
      _syncRowMerges();
    } else {
      _animation.forward(from: 0);
    }
  }

  void _scheduleRevealCaret() {
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (!mounted ||
          !_focus.hasFocus ||
          !_horizontalScroll.hasClients ||
          !widget.controller.selection.isValid) {
        return;
      }
      final surface = _surfaceKey.currentContext?.findRenderObject();
      final viewport = _viewportKey.currentContext?.findRenderObject();
      if (surface is! _RenderBatchPills || viewport is! RenderBox) return;
      final editable = _findEditable(surface);
      if (editable == null) return;
      final origin = editable.localToGlobal(Offset.zero, ancestor: viewport);
      final caret = editable
          .getLocalRectForCaret(
            TextPosition(offset: widget.controller.selection.extentOffset),
          )
          .shift(origin);
      final delta = caret.right > viewport.size.width - 12
          ? caret.right - viewport.size.width + 12
          : caret.left < 12
          ? caret.left - 12
          : 0.0;
      if (delta.abs() > 0.5) {
        _horizontalScroll.jumpTo(
          (_horizontalScroll.offset + delta).clamp(
            0.0,
            _horizontalScroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateActiveRow);
    _focus.dispose();
    _horizontalScroll.dispose();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge!.copyWith(
      color: widget.theme.textPrimary,
      fontSize: 14,
      height: 2.7,
    );
    final textInset = widget.controller.text.isNotEmpty
        ? _platformGutter + _pillHorizontalPadding + 4
        : _focus.hasFocus
        ? _platformIconSlotWidth + 4
        : _pillHorizontalPadding;
    final field = _BatchPillSurface(
      key: _surfaceKey,
      controller: widget.controller,
      theme: widget.theme,
      focusNode: _focus,
      selectionColor:
          DefaultSelectionStyle.of(context).selectionColor ??
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.40),
      animation: _animation,
      merge: _merge,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, input) {
          final lines = widget.controller._currentLines;
          return _BatchRows(
            lines: lines,
            iconRows: [
              for (var row = 0; row < lines.length; row++)
                if (_showRowIndicator(lines[row], row)) row,
            ],
            children: [
              input!,
              for (var row = 0; row < lines.length; row++)
                if (_showRowIndicator(lines[row], row))
                  lines[row].text.trim().isEmpty
                      ? Icon(
                          Icons.chevron_right,
                          key: ValueKey('batch-active-row-$row'),
                          color: widget.theme.accent,
                          size: 18,
                        )
                      : _rowPlatformIcon(lines[row], row),
            ],
          );
        },
        child: DefaultSelectionStyle.merge(
          selectionColor: Colors.transparent,
          child: TextField(
            key: const ValueKey('batch-games-input'),
            controller: widget.controller,
            focusNode: _focus,
            minLines: 8,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            cursorHeight: MediaQuery.textScalerOf(context).scale(14) * 1.25,
            style: style,
            strutStyle: const StrutStyle(
              fontSize: 14,
              height: 2.7,
              forceStrutHeight: true,
            ),
            selectionHeightStyle: ui.BoxHeightStyle.strut,
            selectionWidthStyle: ui.BoxWidthStyle.tight,
            decoration: InputDecoration(
              constraints: const BoxConstraints(minHeight: 0),
              contentPadding: EdgeInsets.fromLTRB(
                textInset,
                6,
                _pillHorizontalPadding + 4,
                6,
              ),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText:
                  'Game Title | XXXXX-XXXXX-XXXXX\nAnother Game | YYYYY-YYYYY-YYYYY\nOr just paste keys on their own',
              hintStyle: TextStyle(color: widget.theme.textHint, height: 2.7),
            ),
            onChanged: widget.onChanged,
          ),
        ),
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InputDecorator(
        isFocused: _focus.hasFocus,
        isHovering: _hovered,
        decoration: InputDecoration(
          constraints: const BoxConstraints(minHeight: 0),
          filled: true,
          fillColor: widget.theme.inputBackground,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 12,
          ),
          border: widget.theme.resolveInputBorder(showTopBorder: true),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => ListenableBuilder(
            listenable: widget.controller,
            child: field,
            builder: (context, child) {
              final painter = TextPainter(
                text: widget.controller.buildTextSpan(
                  context: context,
                  style: style,
                  withComposing: false,
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final width = math.max(
                constraints.maxWidth,
                painter.width +
                    _platformGutter +
                    2 * (_pillHorizontalPadding + 4) +
                    4,
              );
              painter.dispose();
              _scheduleRevealCaret();
              // Each newline stays one game row, even when its title/key is long.
              return SizedBox(
                key: _viewportKey,
                width: constraints.maxWidth,
                child: Scrollbar(
                  controller: _horizontalScroll,
                  child: SingleChildScrollView(
                    key: const ValueKey('batch-games-horizontal-scroll'),
                    controller: _horizontalScroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: width, child: child),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _rowPlatformIcon(_BatchLine line, int row) {
    final platform =
        widget.platformOverride ??
        PlatformDetector.detectPlatform(line.parts?.key ?? '');
    return Tooltip(
      message: widget.platformOverride == null
          ? 'Detected key type: ${platform.displayName}'
          : 'Platform Override: ${platform.displayName}',
      child: PlatformIcon(
        key: ValueKey('batch-platform-$row'),
        platform: platform,
        size: 18,
        color: platform == GamePlatform.other && widget.platformOverride == null
            ? widget.theme.textHint
            : widget.theme.accent,
      ),
    );
  }

  bool _showRowIndicator(_BatchLine line, int row) => line.text.trim().isEmpty
      ? row == _active
      : !line.text.trimLeft().startsWith('#');
}

/// The editor determines the height; indicators follow its rendered row centers.
class _BatchRows extends MultiChildRenderObjectWidget {
  const _BatchRows({
    required this.lines,
    required this.iconRows,
    required super.children,
  });
  final List<_BatchLine> lines;
  final List<int> iconRows;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBatchRows(lines, iconRows);

  @override
  void updateRenderObject(BuildContext context, _RenderBatchRows renderObject) {
    renderObject.lines = lines;
    renderObject.iconRows = iconRows;
    renderObject.markNeedsLayout();
  }
}

class _BatchRowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderBatchRows extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderBatchRows(this.lines, this.iconRows);
  List<_BatchLine> lines;
  List<int> iconRows;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _BatchRowParentData();
    }
  }

  @override
  void performLayout() {
    final input = firstChild!;
    input.layout(
      BoxConstraints.tightFor(width: constraints.maxWidth),
      parentUsesSize: true,
    );
    size = constraints.constrain(input.size);
    final inputData = input.parentData! as ContainerBoxParentData<RenderBox>;
    inputData.offset = Offset.zero;
    final editable = _findEditable(input);
    var indicator = inputData.nextSibling;
    for (final row in iconRows) {
      if (indicator == null) break;
      indicator.layout(
        const BoxConstraints(maxWidth: 24, maxHeight: 24),
        parentUsesSize: true,
      );
      final line = lines[row];
      final boxes = line.text.isEmpty || editable == null
          ? <ui.TextBox>[]
          : editable.getBoxesForSelection(
              TextSelection(
                baseOffset: line.offset,
                extentOffset: line.offset + 1,
              ),
            );
      final rect = boxes.isEmpty ? null : boxes.first.toRect();
      var center = rect?.center.dy;
      if (editable != null && center == null) {
        // Use an existing row as the vertical anchor, including blank lines.
        // Reading the caret during ancestor layout would read a descendant size.
        for (var anchor = 0; anchor < lines.length; anchor++) {
          if (lines[anchor].text.isEmpty) continue;
          final anchorBoxes = editable.getBoxesForSelection(
            TextSelection(
              baseOffset: lines[anchor].offset,
              extentOffset: lines[anchor].offset + 1,
            ),
          );
          if (anchorBoxes.isNotEmpty) {
            center =
                anchorBoxes.first.toRect().center.dy +
                (row - anchor) * editable.preferredLineHeight;
            break;
          }
        }
        center ??= (row + 0.5) * editable.preferredLineHeight;
      }
      center =
          editable?.localToGlobal(Offset(0, center ?? 0), ancestor: input).dy ??
          0;
      final data = indicator.parentData! as ContainerBoxParentData<RenderBox>;
      data.offset = Offset(
        (_platformIconSlotWidth - indicator.size.width) / 2,
        center - indicator.size.height / 2,
      );
      indicator = data.nextSibling;
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
    firstChild!.getDryLayout(
      BoxConstraints.tightFor(width: constraints.maxWidth),
    ),
  );
  @override
  double computeMinIntrinsicHeight(double width) =>
      firstChild!.getMinIntrinsicHeight(width);
  @override
  double computeMaxIntrinsicHeight(double width) =>
      firstChild!.getMaxIntrinsicHeight(width);
  @override
  double computeMinIntrinsicWidth(double height) =>
      firstChild!.getMinIntrinsicWidth(height);
  @override
  double computeMaxIntrinsicWidth(double height) =>
      firstChild!.getMaxIntrinsicWidth(height);
  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);
  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

RenderEditable? _findEditable(RenderObject root) {
  if (root is RenderEditable) return root;
  RenderEditable? result;
  root.visitChildren((child) => result ??= _findEditable(child));
  return result;
}

class _BatchPillSurface extends SingleChildRenderObjectWidget {
  const _BatchPillSurface({
    super.key,
    required this.controller,
    required this.theme,
    required this.focusNode,
    required this.selectionColor,
    required this.animation,
    required this.merge,
    required super.child,
  });
  final BatchGamesEditingController controller;
  final AppThemeData theme;
  final FocusNode focusNode;
  final Color selectionColor;
  final Animation<double> animation;
  final double Function(int) merge;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBatchPills(this);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBatchPills renderObject,
  ) {
    renderObject.configuration = this;
  }
}

class _RenderBatchPills extends RenderProxyBox {
  _RenderBatchPills(this._configuration);
  _BatchPillSurface _configuration;

  set configuration(_BatchPillSurface value) {
    if (attached) _unlisten();
    _configuration = value;
    if (attached) _listen();
    markNeedsPaint();
  }

  void _listen() {
    _configuration.controller.addListener(markNeedsPaint);
    _configuration.animation.addListener(markNeedsPaint);
    _configuration.focusNode.addListener(markNeedsPaint);
  }

  void _unlisten() {
    _configuration.controller.removeListener(markNeedsPaint);
    _configuration.animation.removeListener(markNeedsPaint);
    _configuration.focusNode.removeListener(markNeedsPaint);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listen();
  }

  @override
  void detach() {
    _unlisten();
    super.detach();
  }

  List<Rect> _boxes(RenderEditable editable, int start, int end) {
    if (start >= end) return [];
    final rects = <Rect>[];
    for (final box in editable.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    )) {
      final rect = box.toRect();
      final index = rects.indexWhere(
        (other) => (other.top - rect.top).abs() < 1,
      );
      if (index < 0) {
        rects.add(rect);
      } else {
        rects[index] = rects[index].expandToInclude(rect);
      }
    }
    return rects;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final editable = _findEditable(this);
    if (editable != null && _configuration.controller.text.isNotEmpty) {
      final origin = MatrixUtils.transformPoint(
        editable.getTransformTo(this),
        Offset.zero,
      );
      final canvas = context.canvas;
      canvas.save();
      canvas.clipRect(offset & size);
      canvas.translate(offset.dx + origin.dx, offset.dy + origin.dy);
      final selection = _configuration.controller.selection;
      final showSelection =
          _configuration.focusNode.hasFocus &&
          selection.isValid &&
          !selection.isCollapsed;
      final lines = _configuration.controller._currentLines;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final start =
            line.offset + line.text.length - line.text.trimLeft().length;
        final end = line.offset + line.text.length;
        final all = _boxes(editable, start, end);
        final highlights = showSelection
            ? _boxes(
                editable,
                math.max(start, selection.start),
                math.min(end, selection.end),
              )
            : const <Rect>[];
        final parts = line.parts;
        final title = parts == null
            ? <Rect>[]
            : _boxes(editable, start, line.offset + parts.titleEnd);
        final key = parts == null
            ? <Rect>[]
            : _boxes(editable, line.offset + parts.keyStart, end);
        final merge = _configuration.merge(i);
        for (final box in all) {
          final bounds = Rect.fromLTRB(
            box.left - _pillHorizontalPadding,
            box.top + 3,
            box.right + _pillHorizontalPadding,
            box.bottom - 3,
          );
          final titles = title.where((r) => (r.top - box.top).abs() < 1);
          final keys = key.where((r) => (r.top - box.top).abs() < 1);
          if (titles.isEmpty || keys.isEmpty) {
            _pill(canvas, bounds, merge: merge, highlights: highlights);
            continue;
          }
          final titleEnd = titles.last.right;
          final keyStart = keys.first.left;
          final seam = (titleEnd + keyStart) / 2;
          final padding = math.min(
            _pillHorizontalPadding,
            math.max(0.0, (keyStart - titleEnd) / 2 - _dividerClearance),
          );
          final left = Rect.fromLTRB(
            bounds.left,
            bounds.top,
            ui.lerpDouble(titleEnd + padding, seam, merge)!,
            bounds.bottom,
          );
          final right = Rect.fromLTRB(
            ui.lerpDouble(keyStart - padding, seam, merge)!,
            bounds.top,
            bounds.right,
            bounds.bottom,
          );
          if (merge >= 0.999) {
            _pill(canvas, bounds, merge: merge, highlights: highlights);
          } else {
            _pill(
              canvas,
              left,
              merge: merge,
              innerRight: true,
              highlights: highlights,
            );
            _pill(
              canvas,
              right,
              merge: merge,
              innerLeft: true,
              highlights: highlights,
            );
          }
          final dividerHalfHeight = math.min(
            editable.cursorHeight / 2,
            bounds.height / 2 - 7,
          );
          canvas.drawLine(
            Offset(seam, bounds.center.dy - dividerHalfHeight),
            Offset(seam, bounds.center.dy + dividerHalfHeight),
            Paint()
              ..color = _configuration.theme.accent.withValues(
                alpha: 0.65 * (1 - math.sin(math.pi * merge)),
              )
              ..strokeWidth = 1.5
              ..strokeCap = StrokeCap.round,
          );
        }
      }
      canvas.restore();
    }
    super.paint(context, offset);
  }

  void _pill(
    Canvas canvas,
    Rect rect, {
    required double merge,
    required List<Rect> highlights,
    bool innerLeft = false,
    bool innerRight = false,
  }) {
    final theme = _configuration.theme;
    final radius = math.min(theme.cornerRadius, rect.height / 2);
    final outer = Radius.circular(radius);
    final inner = Radius.circular(radius * (1 - merge));
    final shape = RRect.fromRectAndCorners(
      rect,
      topLeft: innerLeft ? inner : outer,
      bottomLeft: innerLeft ? inner : outer,
      topRight: innerRight ? inner : outer,
      bottomRight: innerRight ? inner : outer,
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..color = Color.alphaBlend(
          theme.accent.withValues(alpha: 0.10 + 0.05 * merge),
          theme.inputBackground,
        ),
    );
    // Keep the native selection range, but confine its paint to each pill.
    if (highlights.isNotEmpty) {
      canvas.save();
      canvas.clipRRect(shape);
      final paint = Paint()..color = _configuration.selectionColor;
      for (final highlight in highlights) {
        if (highlight.overlaps(rect)) canvas.drawRect(highlight, paint);
      }
      canvas.restore();
    }
    // Suppress the inner strokes as the two pills join into one outline.
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        rect.left + (innerLeft ? ui.lerpDouble(-1, 1.5, merge)! : -1),
        rect.top - 1,
        rect.right - (innerRight ? ui.lerpDouble(-1, 1.5, merge)! : -1),
        rect.bottom + 1,
      ),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..color = theme.accent.withValues(alpha: 0.25 + 0.45 * merge)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.restore();
  }
}
