// Dart twin of EmailTextTests.swift (HisabCore/Tests/HisabCoreTests).
import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

void main() {
  const email = '''
<html><head><style>p { color: #333; font-family: Arial; }</style></head>
<body><!-- tracking --><table><tr><td>
<p>Dear Customer,</p>
<p>Rs.450.00 has been debited from account **1234 to VPA vedant@okaxis on 22-09-26.</p>
<p>Your UPI transaction reference number is&nbsp;627775786529.</p>
<p>Not you? Call us &amp; block UPI &#8377; &#x20B9; &amp;lt;</p>
</td></tr></table></body></html>''';

  test('SMS passes through untouched', () {
    const sms = 'Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA '
        'vedant@okaxis. UPI Ref No 627775786529 <limit 5000>';
    expect(EmailText.plain(sms), sms);
  });

  test('an HTML email becomes its visible text', () {
    expect(
        EmailText.plain(email),
        'Dear Customer, Rs.450.00 has been debited from account **1234 to VPA '
        'vedant@okaxis on 22-09-26. Your UPI transaction reference number is '
        '627775786529. Not you? Call us & block UPI ₹ ₹ &lt;');
  });
}
