// What the native side hands over for an opened file or a hisab:// link, and
// where each lands. Same routes as the Swift app's DeepLinkRouter.
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/services/capture_notifier.dart';
import 'package:hisab/services/incoming_router.dart';

void main() {
  setUp(() {
    IncomingRouter.file.value = null;
    IncomingRouter.link.value = null;
    CaptureRouter.reviewRequest.value = null;
  });

  test('an opened file is parked for the import flow', () {
    IncomingRouter.route(
        {'kind': 'file', 'path': '/tmp/incoming/x-hdfc.pdf', 'name': 'hdfc.pdf'});
    expect(IncomingRouter.file.value?.name, 'hdfc.pdf');
    expect(IncomingRouter.file.value?.path, '/tmp/incoming/x-hdfc.pdf');
  });

  test('a memo link opens that memo on the dashboard', () {
    IncomingRouter.route({'kind': 'link', 'url': 'hisab://memo/abc123'});
    expect(CaptureRouter.reviewRequest.value, 'abc123');
    expect(IncomingRouter.link.value, LinkTarget.dashboard);
  });

  test('a transaction link goes to Transactions', () {
    IncomingRouter.route(
        {'kind': 'link', 'url': 'hisab://transaction/0B5C-11'});
    expect(IncomingRouter.link.value, LinkTarget.transactions);
    expect(CaptureRouter.reviewRequest.value, isNull);
  });

  test('any other link just opens the dashboard', () {
    IncomingRouter.route({'kind': 'link', 'url': 'hisab://review'});
    expect(IncomingRouter.link.value, LinkTarget.dashboard);
  });
}
