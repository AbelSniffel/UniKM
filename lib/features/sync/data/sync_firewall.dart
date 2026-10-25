import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../domain/sync_ports.dart';

class WindowsFirewallCheckResult {
  const WindowsFirewallCheckResult({
    required this.available,
    this.hasPrivateAllow = false,
    this.hasPublicAllow = false,
  });

  final bool available;
  final bool hasPrivateAllow;
  final bool hasPublicAllow;

  bool get fullyAllowed => hasPrivateAllow && hasPublicAllow;
}

class LinuxFirewallCheckResult {
  const LinuxFirewallCheckResult({
    required this.available,
    this.active = false,
    this.uniKMAllowed = false,
    this.udpPortAllowed = false,
    this.tcpPortAllowed = false,
    this.firewallTool = '',
  });

  final bool available;
  final bool active;
  final bool uniKMAllowed;
  final bool udpPortAllowed;
  final bool tcpPortAllowed;
  final String firewallTool;

  bool get fullyAllowed => uniKMAllowed && udpPortAllowed && tcpPortAllowed;
}

typedef FirewallProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      required bool runInShell,
    });

/// Owns platform firewall inspection and commands independently of pairing,
/// discovery, and database synchronization. Existing service methods delegate
/// here so callers retain their public API.
class SyncFirewall {
  SyncFirewall({FirewallProcessRunner? runProcess})
    : _runProcess = runProcess ?? Process.run;

  final FirewallProcessRunner _runProcess;

  static const String _firewallAppRuleName = 'UniKM';
  static const String _legacyUdpRuleName = 'UniKM Device Sync (UDP Discovery)';
  static const String _legacyTcpRuleName = 'UniKM Device Sync (TCP Transfer)';

  String _normalizeWindowsPath(String value) =>
      p.normalize(value).replaceAll('/', r'\').toLowerCase().trim();

  Future<WindowsFirewallCheckResult?> checkWindowsFirewallAccess() async {
    if (kIsWeb || !Platform.isWindows) return null;

    final executablePath = _normalizeWindowsPath(Platform.resolvedExecutable);
    try {
      final result = await _runProcess('netsh.exe', [
        'advfirewall',
        'firewall',
        'show',
        'rule',
        'name=all',
        'verbose',
      ], runInShell: true);

      final output = (result.stdout as String).trim();
      if (output.isEmpty) {
        return const WindowsFirewallCheckResult(available: false);
      }

      var hasPrivateAllow = false;
      var hasPublicAllow = false;

      var currentProgram = '';
      var currentProfiles = '';
      var currentAction = '';

      void commitRule() {
        if (currentProgram == executablePath && currentAction == 'allow') {
          if (currentProfiles.contains('private') ||
              currentProfiles.contains('all')) {
            hasPrivateAllow = true;
          }
          if (currentProfiles.contains('public') ||
              currentProfiles.contains('all')) {
            hasPublicAllow = true;
          }
        }

        currentProgram = '';
        currentProfiles = '';
        currentAction = '';
      }

      for (final rawLine in const LineSplitter().convert(output)) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;

        final lower = line.toLowerCase();
        if (lower.startsWith('rule name:')) {
          commitRule();
          continue;
        }

        final delimiter = line.indexOf(':');
        if (delimiter <= 0) continue;

        final value = line.substring(delimiter + 1).trim();
        if (lower.startsWith('program:')) {
          currentProgram = _normalizeWindowsPath(value);
          continue;
        }

        if (lower.startsWith('profiles:') || lower.startsWith('profile:')) {
          currentProfiles = value.toLowerCase();
          continue;
        }

        if (lower.startsWith('action:')) {
          final action = value.toLowerCase();
          currentAction = action.contains('allow') ? 'allow' : action;
        }
      }

      commitRule();

      return WindowsFirewallCheckResult(
        available: true,
        hasPrivateAllow: hasPrivateAllow,
        hasPublicAllow: hasPublicAllow,
      );
    } catch (_) {
      return const WindowsFirewallCheckResult(available: false);
    }
  }

  Future<bool> grantWindowsFirewallAccess() async {
    if (kIsWeb || !Platform.isWindows) return false;

    final appPath = Platform.resolvedExecutable;
    final scriptPath = p.join(
      Directory.systemTemp.path,
      'unikm_firewall_${DateTime.now().millisecondsSinceEpoch}.cmd',
    );
    final scriptFile = File(scriptPath);

    try {
      final lines = <String>[
        '@echo off',
        'netsh advfirewall firewall delete rule name="$_firewallAppRuleName"',
        'netsh advfirewall firewall delete rule name="$_legacyUdpRuleName"',
        'netsh advfirewall firewall delete rule name="$_legacyTcpRuleName"',
        'netsh firewall delete allowedprogram program="$appPath"',
        'netsh advfirewall firewall add rule name="$_firewallAppRuleName" dir=in action=allow enable=yes profile=private,public program="$appPath" remoteip=LocalSubnet',
        'exit /b %ERRORLEVEL%',
      ];
      await scriptFile.writeAsString(lines.join('\r\n'), flush: true);

      final quotedScriptPath = scriptPath.replaceAll("'", "''");
      final elevateCommand =
          "\$p = Start-Process -FilePath '$quotedScriptPath' -Verb RunAs -Wait -PassThru; "
          'exit \$p.ExitCode';

      final result = await _runProcess('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        elevateCommand,
      ], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    } finally {
      try {
        if (await scriptFile.exists()) await scriptFile.delete();
      } catch (_) {}
    }
  }

  Future<bool> openWindowsFirewallAllowedApps() async {
    if (kIsWeb || !Platform.isWindows) return false;

    try {
      await Process.start('control.exe', [
        '/name',
        'Microsoft.WindowsFirewall',
        '/page',
        'pageConfigureApps',
      ], runInShell: true);
      return true;
    } catch (_) {
      try {
        await Process.start('control.exe', ['firewall.cpl'], runInShell: true);
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> openWindowsFirewallAdvancedSettings() async {
    if (kIsWeb || !Platform.isWindows) return false;

    try {
      await Process.start('wf.msc', const [], runInShell: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<LinuxFirewallCheckResult?> checkLinuxFirewallAccess() async {
    if (kIsWeb || !Platform.isLinux) return null;

    // Try ufw first (most common on Ubuntu/Debian)
    try {
      final result = await _runProcess('ufw', ['status'], runInShell: true);
      final output = (result.stdout as String).trim().toLowerCase();
      if (output.contains('active')) {
        // Check if UniKM app path is allowed
        final appPath = Platform.resolvedExecutable;
        final appAllowed =
            output.contains(appPath.toLowerCase()) ||
            output.contains(SyncPorts.discovery.toString()) ||
            output.contains(SyncPorts.transfer.toString());
        return LinuxFirewallCheckResult(
          available: true,
          active: true,
          uniKMAllowed: appAllowed,
          udpPortAllowed: output.contains(SyncPorts.discovery.toString()),
          tcpPortAllowed: output.contains(SyncPorts.transfer.toString()),
          firewallTool: 'ufw',
        );
      }
      // ufw is installed but not active
      return LinuxFirewallCheckResult(
        available: true,
        active: false,
        firewallTool: 'ufw',
      );
    } catch (_) {}

    // Try firewalld (common on Fedora/RHEL/CentOS)
    try {
      final result = await _runProcess('firewall-cmd', [
        '--state',
      ], runInShell: true);
      final output = (result.stdout as String).trim().toLowerCase();
      if (output == 'running') {
        // Check if ports are open
        final udpCheck = await _runProcess('firewall-cmd', [
          '--query-port=${SyncPorts.discovery}/udp',
        ], runInShell: true);
        final tcpCheck = await _runProcess('firewall-cmd', [
          '--query-port=${SyncPorts.transfer}/tcp',
        ], runInShell: true);
        final udpOpen =
            (udpCheck.stdout as String).trim().toLowerCase() == 'yes';
        final tcpOpen =
            (tcpCheck.stdout as String).trim().toLowerCase() == 'yes';
        return LinuxFirewallCheckResult(
          available: true,
          active: true,
          uniKMAllowed: udpOpen && tcpOpen,
          udpPortAllowed: udpOpen,
          tcpPortAllowed: tcpOpen,
          firewallTool: 'firewalld',
        );
      }
      return LinuxFirewallCheckResult(
        available: true,
        active: false,
        firewallTool: 'firewalld',
      );
    } catch (_) {}

    // Try iptables as fallback
    try {
      final result = await _runProcess('iptables', [
        '-L',
        '-n',
      ], runInShell: true);
      final output = (result.stdout as String).trim().toLowerCase();
      if (result.exitCode == 0 && output.isNotEmpty) {
        final hasRule =
            output.contains(SyncPorts.discovery.toString()) ||
            output.contains(SyncPorts.transfer.toString());
        return LinuxFirewallCheckResult(
          available: true,
          active: true,
          uniKMAllowed: hasRule,
          udpPortAllowed: hasRule,
          tcpPortAllowed: hasRule,
          firewallTool: 'iptables',
        );
      }
    } catch (_) {}

    return const LinuxFirewallCheckResult(available: false);
  }

  /// Try to run a command with elevated privileges.
  /// Attempts pkexec first (graphical polkit dialog), then sudo -n (cached
  /// credentials). Returns true if the command succeeded (exit code 0).
  Future<bool> _runWithElevation(String command, List<String> args) async {
    // Try pkexec (graphical polkit prompt)
    try {
      final result = await _runProcess('pkexec', [
        command,
        ...args,
      ], runInShell: true);
      if (result.exitCode == 0) return true;
      // Exit 126 = auth cancelled by user, 127 = pkexec not found — fall through
      if (result.exitCode != 126 && result.exitCode != 127) return false;
    } catch (_) {}

    // Fallback: sudo -n (non-interactive, requires cached credentials)
    try {
      final result = await _runProcess('sudo', [
        '-n',
        command,
        ...args,
      ], runInShell: true);
      if (result.exitCode == 0) return true;
    } catch (_) {}

    return false;
  }

  // Linux rule arguments shared by grant and clear, so both always name the
  // same rules for the discovery (UDP) and transfer (TCP) ports.
  static List<String> _ufwRule(int port, String protocol) => [
    'allow',
    'from',
    'any',
    'to',
    'any',
    'port',
    '$port',
    'proto',
    protocol,
  ];

  static List<String> _iptablesRule(String action, String protocol, int port) =>
      [action, 'INPUT', '-p', protocol, '--dport', '$port', '-j', 'ACCEPT'];

  Future<bool> grantLinuxFirewallAccess() async {
    if (kIsWeb || !Platform.isLinux) return false;

    // Try ufw
    try {
      final udpOk = await _runWithElevation(
        'ufw',
        _ufwRule(SyncPorts.discovery, 'udp'),
      );
      if (udpOk) {
        await _runWithElevation('ufw', _ufwRule(SyncPorts.transfer, 'tcp'));
        return true;
      }
    } catch (_) {}

    // Try firewalld
    try {
      final udpOk = await _runWithElevation('firewall-cmd', [
        '--add-port=${SyncPorts.discovery}/udp',
        '--permanent',
      ]);
      if (udpOk) {
        await _runWithElevation('firewall-cmd', [
          '--add-port=${SyncPorts.transfer}/tcp',
          '--permanent',
        ]);
        await _runWithElevation('firewall-cmd', ['--reload']);
        return true;
      }
    } catch (_) {}

    // Try iptables as fallback
    try {
      final udpOk = await _runWithElevation(
        'iptables',
        _iptablesRule('-A', 'udp', SyncPorts.discovery),
      );
      if (udpOk) {
        await _runWithElevation(
          'iptables',
          _iptablesRule('-A', 'tcp', SyncPorts.transfer),
        );
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// Remove the firewall rules added by [grantLinuxFirewallAccess].
  Future<bool> clearLinuxFirewallAccess() async {
    if (kIsWeb || !Platform.isLinux) return false;

    bool anyRemoved = false;

    // Try ufw
    try {
      final udpOk = await _runWithElevation('ufw', [
        'delete',
        ..._ufwRule(SyncPorts.discovery, 'udp'),
      ]);
      if (udpOk) anyRemoved = true;
      await _runWithElevation('ufw', [
        'delete',
        ..._ufwRule(SyncPorts.transfer, 'tcp'),
      ]);
    } catch (_) {}

    // Try firewalld
    try {
      final udpOk = await _runWithElevation('firewall-cmd', [
        '--remove-port=${SyncPorts.discovery}/udp',
        '--permanent',
      ]);
      if (udpOk) anyRemoved = true;
      await _runWithElevation('firewall-cmd', [
        '--remove-port=${SyncPorts.transfer}/tcp',
        '--permanent',
      ]);
      if (anyRemoved) await _runWithElevation('firewall-cmd', ['--reload']);
    } catch (_) {}

    // Try iptables
    try {
      final udpOk = await _runWithElevation(
        'iptables',
        _iptablesRule('-D', 'udp', SyncPorts.discovery),
      );
      if (udpOk) anyRemoved = true;
      await _runWithElevation(
        'iptables',
        _iptablesRule('-D', 'tcp', SyncPorts.transfer),
      );
    } catch (_) {}

    return anyRemoved;
  }
}
