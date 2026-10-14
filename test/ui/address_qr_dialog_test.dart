import 'dart:async';

import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_balance_summary.dart';
import 'package:bitcoin_wallet/src/crypto/bitcoin/models/bitcoin_history_entry.dart';
import 'package:bitcoin_wallet/src/ui/widgets/address/address_qr_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const balance = BitcoinBalanceSummary(
    totalText: '0.00001000 BTC',
    confirmedText: '0.00001000 BTC',
    utxos: [
      BitcoinUtxoSummary(
        txid: 'utxo-id',
        vout: 0,
        valueText: '0.00001000 BTC',
        confirmed: true,
      ),
    ],
  );

  Future<void> openHistory(WidgetTester tester) async {
    await tester.ensureVisible(find.text('取引履歴'));
    await tester.tap(find.text('取引履歴'));
    await tester.pump();
  }

  testWidgets('履歴を初回選択時に取得し、タブを戻しても再取得しない', (tester) async {
    final result = Completer<List<BitcoinHistoryEntry>>();
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddressQrDialog(
            name: 'Test',
            address: 'address',
            loadBalance: () async => balance,
            loadHistory: () {
              loads++;
              return result.future;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, 0);
    expect(find.text('txid: utxo-id'), findsOneWidget);
    await openHistory(tester);
    expect(find.text('取引履歴を取得中…'), findsOneWidget);
    result.complete([
      BitcoinHistoryEntry(
        txid: 'history-id',
        balanceChange: -6000,
        confirmed: true,
        confirmedAt: DateTime.utc(2026, 10, 14),
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('出金: -0.00006000 BTC'), findsOneWidget);
    expect(find.text('txid: history-id'), findsOneWidget);
    expect(find.textContaining('承認日時:'), findsOneWidget);
    expect(find.text('txid: utxo-id'), findsNothing);
    await tester.ensureVisible(find.text('UTXO'));
    await tester.tap(find.text('UTXO'));
    await tester.pumpAndSettle();
    expect(find.text('txid: utxo-id'), findsOneWidget);
    await openHistory(tester);
    await tester.pumpAndSettle();
    expect(loads, 1);
  });

  testWidgets('残高取得が失敗しても履歴タブを開けて、履歴取得失敗は再試行できる', (tester) async {
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddressQrDialog(
            name: 'Test',
            address: 'address',
            loadBalance: () async => throw Exception('balance error'),
            loadHistory: () async {
              if (++loads == 1) throw Exception('history error');
              return [];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openHistory(tester);
    await tester.pumpAndSettle();
    expect(find.text('取引履歴を取得できませんでした。'), findsOneWidget);
    await tester.ensureVisible(find.text('取引履歴を再取得'));
    await tester.tap(find.text('取引履歴を再取得'));
    await tester.pumpAndSettle();
    expect(find.text('取引履歴はありません'), findsOneWidget);
    expect(loads, 2);
  });
}
