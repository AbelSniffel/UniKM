/// Shared by discovery, TCP transfer, and platform firewall rules.
abstract final class SyncPorts {
  static const int discovery = 45871;
  static const int transfer = 45872;
}
