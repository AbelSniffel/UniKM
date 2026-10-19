import 'package:flutter_riverpod/flutter_riverpod.dart';

/// An independent, in-memory value that resets with its provider's lifecycle.
NotifierProvider<SessionValue<T>, T> sessionValueProvider<T>(T initialValue) =>
    NotifierProvider<SessionValue<T>, T>(() => SessionValue(initialValue));

class SessionValue<T> extends Notifier<T> {
  SessionValue(this.initialValue);

  final T initialValue;

  @override
  T build() => initialValue;

  void set(T value) => state = value;

  void reset() => state = initialValue;
}
