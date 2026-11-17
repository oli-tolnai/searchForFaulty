import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import 'api/models.dart';
import 'api/webapp.dart';
import 'storage.dart';

const notificationTask = 'console-deal-finder-notifications';

String newDeviceId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class DeliveryFiles {
  DeliveryFiles(this.directory);
  final Directory directory;

  static Future<DeliveryFiles> open() async {
    final parent = await getApplicationSupportDirectory();
    final directory = Directory('${parent.path}/notifications');
    await directory.create(recursive: true);
    return DeliveryFiles(directory);
  }

  File file(String name) => File('${directory.path}/$name');

  Future<String?> deviceId({bool create = false}) async {
    final device = file('device');
    if (!await device.exists()) {
      if (!create) return null;
      await _replace(device, newDeviceId());
    }
    final id = await device.readAsString();
    if (!notificationUuid.hasMatch(id)) invalidResponse();
    return id;
  }

  Future<bool> enabled() async => !await file('disabled').exists();
  Future<void> setEnabled(bool enabled) async {
    final disabled = file('disabled');
    if (enabled) {
      if (await disabled.exists()) await disabled.delete();
    } else {
      await disabled.create();
    }
  }

  Future<bool> permissionExplained() => file('permission-explained').exists();
  Future<void> markPermissionExplained() async {
    await file('permission-explained').create();
  }

  File lastPullFile(String stateId) => file('$stateId-last-pull');
  Future<DateTime?> lastPull(String stateId) async {
    final marker = lastPullFile(stateId);
    return await marker.exists()
        ? DateTime.tryParse(await marker.readAsString())
        : null;
  }

  Future<void> markPulled(String stateId, DateTime now) =>
      _replace(lastPullFile(stateId), now.toUtc().toIso8601String());

  Future<void> _replace(File target, String value) async {
    final pending = file('pending-${newDeviceId()}');
    await pending.writeAsString(value, flush: true);
    await pending.rename(target.path);
  }

  File shownFile(String id) {
    if (!notificationUuid.hasMatch(id)) invalidResponse();
    return file('$id.shown');
  }

  Future<bool> wasShown(String id) => shownFile(id).exists();

  Future<bool> deliverOnce(
    QueuedNotification notice,
    Future<void> Function(QueuedNotification) show,
  ) async {
    final shown = shownFile(notice.id);
    if (await shown.exists()) return true;
    // The foreground and WorkManager use separate engines. The exclusive create
    // admits only one engine even when both receive an unacknowledged notice.
    final claim = file('${notice.id}.claim');
    try {
      await claim.create(exclusive: true);
    } on PathExistsException {
      return await shown.exists();
    }
    try {
      if (await shown.exists()) return true;
      if (!await enabled() || !notice.expiresAt.isAfter(DateTime.now())) {
        return false;
      }
      await show(notice);
      await shown.create();
      return true;
    } finally {
      await claim.delete();
    }
  }

  Future<void> prune() async {
    final now = DateTime.now();
    await for (final entry in directory.list()) {
      if (entry is! File) continue;
      final age = now.difference((await entry.stat()).modified);
      final ageLimit = entry.path.endsWith('.claim')
          ? const Duration(minutes: 10)
          : entry.path.endsWith('.shown')
          ? const Duration(days: 2)
          : null;
      if (ageLimit != null && age > ageLimit) {
        try {
          await entry.delete();
        } on PathNotFoundException {
          // Another engine pruned the same expired entry.
        }
      }
    }
  }
}

Future<void> retrieveNotifications({
  required Future<bool> Function() enabled,
  required Future<List<QueuedNotification>> Function() pull,
  required Future<void> Function(List<String>) acknowledge,
  required Future<bool> Function(QueuedNotification) deliver,
  required Future<void> Function() markPulled,
  DateTime Function() clock = DateTime.now,
}) async {
  if (!await enabled()) return;
  final notices = await pull();
  await markPulled();
  final delivered = <String>{};
  try {
    for (final notice in notices) {
      if (!await enabled()) break;
      if (notice.expiresAt.isAfter(clock()) &&
          !delivered.contains(notice.id) &&
          await deliver(notice)) {
        delivered.add(notice.id);
      }
    }
  } finally {
    if (delivered.isNotEmpty) await acknowledge(delivered.toList());
  }
}

class LocalNotifications {
  final plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;

  Future<void> initialize([void Function(String?)? onTap]) =>
      _initializing ??= _initialize(onTap);

  Future<void> _initialize(void Function(String?)? onTap) async {
    final ready = await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        windows: WindowsInitializationSettings(
          appName: 'Console Deal Finder',
          appUserModelId: 'hu.consoledealfinder.ConsoleDealFinder',
          guid: 'f250ad77-2746-4ca2-972e-34f520eca930',
        ),
      ),
      onDidReceiveNotificationResponse: onTap == null
          ? null
          : (response) => onTap(response.payload),
    );
    if (ready == false) {
      throw const AppFailure('A helyi értesítések nem érhetők el.');
    }
    if (Platform.isAndroid && onTap != null) {
      final launch = await plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        onTap(launch?.notificationResponse?.payload);
      }
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get android => plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<bool> allowed() async =>
      !Platform.isAndroid || await android?.areNotificationsEnabled() == true;

  Future<bool> requestPermission() async =>
      !Platform.isAndroid ||
      await android?.requestNotificationsPermission() == true;

  Future<void> show(QueuedNotification notice) => plugin.show(
    id: int.parse(notice.id.substring(0, 8), radix: 16) & 0x7fffffff,
    title: notice.title,
    body: notice.body,
    payload: notice.url?.toString() ?? '',
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        'console_deal_finder',
        'Konzolértesítések',
        channelDescription: 'Figyelt aukciók és új konzolajánlatok',
        importance: Importance.high,
        priority: notice.kind == 'auction_closing'
            ? Priority.high
            : Priority.defaultPriority,
        styleInformation: BigTextStyleInformation(notice.body),
        onlyAlertOnce: true,
      ),
    ),
  );

  Future<void> poll(WebappClient client, DeliveryFiles files) async {
    if (!await files.enabled()) return;
    final device = await files.deviceId();
    if (device == null) return;
    await initialize();
    if (!await allowed()) return;
    await files.prune();
    await retrieveNotifications(
      enabled: files.enabled,
      pull: () => client.pullNotifications(device),
      acknowledge: (ids) => client.acknowledgeNotifications(device, ids),
      deliver: (notice) => files.deliverOnce(notice, show),
      markPulled: () =>
          files.markPulled(client.settings.stateId, DateTime.now()),
    );
  }
}

Future<void> openAndroidAppSettings() =>
    const MethodChannel('hu.consoledealfinder/settings')
        .invokeMethod<void>('openAppSettings');

@pragma('vm:entry-point')
void dispatchNotificationTask() {
  Workmanager().executeTask((task, input) async {
    if (task != notificationTask) return true;
    try {
      final files = await DeliveryFiles.open();
      if (!await files.enabled()) return true;
      final settings = await const SettingsStore().read();
      if (settings != null) {
        await LocalNotifications().poll(WebappClient(settings), files);
      }
      return true;
    } on Exception {
      return false;
    }
  });
}

Future<void> configureNotificationTask(bool enabled) async {
  if (!Platform.isAndroid) return;
  final manager = Workmanager();
  if (enabled) {
    await manager.initialize(dispatchNotificationTask);
    await manager.registerPeriodicTask(
      notificationTask,
      notificationTask,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } else {
    await manager.cancelByUniqueName(notificationTask);
  }
}
