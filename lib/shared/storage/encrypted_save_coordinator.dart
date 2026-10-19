/// Serializes saves and acknowledges only revisions whose writer completed.
/// A failed save remains dirty; a later request can retry it.
class EncryptedSaveCoordinator {
  EncryptedSaveCoordinator(this.write);

  final Future<void> Function() write;
  Future<void> _tail = Future.value();
  int _requestedRevision = 0;
  int _savedRevision = 0;

  int get savedRevision => _savedRevision;
  bool get isDirty => _savedRevision < _requestedRevision;

  Future<void> save() {
    final revision = ++_requestedRevision;
    final result = _tail.then((_) async {
      await write();
      _savedRevision = revision;
    });
    // Keep the queue usable after failure, while returning failure to the caller.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> flush() async {
    await _tail;
    if (isDirty) await save();
  }
}
