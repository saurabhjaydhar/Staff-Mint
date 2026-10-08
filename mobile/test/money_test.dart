import 'package:flutter_test/flutter_test.dart';
import 'package:staffmint/core/utils/money.dart';
import 'package:staffmint/core/utils/phone.dart';

void main() {
  group('Money.format (paise → ₹ with Indian grouping)', () {
    test('whole rupees have no decimals', () {
      expect(Money.format(1200000), '₹12,000');
      expect(Money.format(0), '₹0');
      expect(Money.format(100), '₹1');
      expect(Money.format(99900), '₹999');
    });

    test('uses lakh / crore grouping', () {
      expect(Money.format(12000000), '₹1,20,000');
      expect(Money.format(1234567800), '₹1,23,45,678');
    });

    test('shows paise only when not a whole rupee', () {
      expect(Money.format(1234550), '₹12,345.50');
      expect(Money.format(5), '₹0.05');
      expect(Money.format(1200000, alwaysShowPaise: true), '₹12,000.00');
    });

    test('negative amounts put the sign before the symbol', () {
      expect(Money.format(-50000), '-₹500');
      expect(Money.signed(50000), '+₹500');
      expect(Money.signed(-50000), '-₹500');
    });

    test('plainRupees drops the symbol', () {
      expect(Money.plainRupees(1500000), '15,000');
    });
  });

  group('Money.parseRupees (owner input → paise)', () {
    test('plain and grouped numbers', () {
      expect(Money.parseRupees('12000'), 1200000);
      expect(Money.parseRupees('12,000'), 1200000);
      expect(Money.parseRupees(' ₹12,000/- '), 1200000);
      expect(Money.parseRupees('Rs. 500'), 50000);
    });

    test('decimals round to paise', () {
      expect(Money.parseRupees('12000.5'), 1200050);
      expect(Money.parseRupees('0.01'), 1);
    });

    test('k and lakh shorthands', () {
      expect(Money.parseRupees('12k'), 1200000);
      expect(Money.parseRupees('1.5 lakh'), 15000000);
    });

    test('invalid input returns null', () {
      expect(Money.parseRupees(''), isNull);
      expect(Money.parseRupees('abc'), isNull);
      expect(Money.parseRupees('-5'), isNull);
    });
  });

  group('Phones', () {
    test('normalises Indian numbers to 10 digits', () {
      expect(Phones.normalize('9876543210'), '9876543210');
      expect(Phones.normalize('+91 98765 43210'), '9876543210');
      expect(Phones.normalize('919876543210'), '9876543210');
      expect(Phones.normalize('09876543210'), '9876543210');
      expect(Phones.normalize('(987) 654-3210'), '9876543210');
    });

    test('rejects invalid numbers', () {
      expect(Phones.normalize('12345'), isNull);
      expect(Phones.normalize('1234567890'), isNull); // must start 6-9
      expect(Phones.normalize(''), isNull);
    });

    test('keeps foreign E.164 numbers', () {
      expect(Phones.normalize('+971501234567'), '+971501234567');
    });

    test('display format', () {
      expect(Phones.display('9876543210'), '+91 98765 43210');
    });
  });
}
