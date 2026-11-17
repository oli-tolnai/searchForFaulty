import 'dart:async';
import 'dart:io';

import 'package:flutter_app/api/models.dart';
import 'package:flutter_app/local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/responses.dart';

void main() {
  late Directory directory;
  late DeliveryFiles files;
  late QueuedNotification notice;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cdf-notifications-');
    files = DeliveryFiles(directory);
    notice = QueuedNotification.fromJson(queuedAuction(DateTime.now()));
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'pull displays the expected content and persists before ack for recovery',
    () async {
      var displays = 0;
      var pulls = 0;
      var acknowledgeAttempts = 0;
      var failed = false;
      Future<void> poll(DeliveryFiles process) => retrieveNotifications(
        enabled: process.enabled,
        pull: () async {
          pulls++;
          return [notice, notice];
        },
        acknowledge: (ids) async {
          expect(ids, [notice.id]);
          if (++acknowledgeAttempts == 1) {
            throw const SocketException('offline');
          }
        },
        deliver: (notice) => process.deliverOnce(notice, (event) async {
          expect(event.title, 'Aukció zárul');
          expect(event.body, 'Ma 19:30-kor zárul: PS5 Slim – 120 €');
          expect(event.url.toString(), 'https://www.ebay.de/itm/123');
          displays++;
        }),
        markPulled: () => process.markPulled('test', DateTime.now()),
      );
      try {
        await poll(files);
      } on SocketException {
        failed = true;
      }
      expect(failed, isTrue);
      expect(await files.lastPull('test'), isNotNull);
      await poll(DeliveryFiles(directory));
      expect(pulls, 2);
      expect(displays, 1);
      expect(acknowledgeAttempts, 2);
    },
  );

  test(
    'foreground and background cannot both display the same notice',
    () async {
      final entered = Completer<void>();
      final resume = Completer<void>();
      final first = files.deliverOnce(notice, (_) async {
        entered.complete();
        await resume.future;
      });
      await entered.future;
      final concurrent = await DeliveryFiles(directory)
          .deliverOnce(notice, (_) async {
            fail('Another engine already claimed the notice.');
          });
      expect(concurrent, isFalse);
      resume.complete();
      expect(await first, isTrue);
      expect(await files.wasShown(notice.id), isTrue);
    },
  );

  test('a disabled device never pulls, displays or acknowledges', () async {
    await files.setEnabled(false);
    await retrieveNotifications(
      enabled: files.enabled,
      pull: () async => fail('Disabled devices must not pull.'),
      acknowledge: (_) async => fail('Disabled devices must not acknowledge.'),
      deliver: (_) async => fail('Disabled devices must not display.'),
      markPulled: () async =>
          fail('Disabled devices must not record a successful pull.'),
    );
    await files.setEnabled(true);
    final id = await files.deviceId(create: true);
    expect(notificationUuid.hasMatch(id!), isTrue);
    expect(await DeliveryFiles(directory).deviceId(), id);
  });

  test(
    'only successful displays are acknowledged and expired items are ignored',
    () async {
      final past = QueuedNotification.fromJson(
        queuedAuction(DateTime.now().subtract(const Duration(hours: 2))),
      );
      var acknowledgements = 0;
      await expectLater(
        retrieveNotifications(
          enabled: () async => true,
          pull: () async => [past, notice],
          acknowledge: (_) async => acknowledgements++,
          deliver: (item) async {
            expect(item, same(notice));
            throw const FileSystemException('notification failed');
          },
          markPulled: () async {},
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(acknowledgements, 0);
      expect(
        notificationListingLink('https://ebay.de.example.test/itm/123'),
        isNull,
      );
    },
  );
}
