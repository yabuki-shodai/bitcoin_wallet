abstract class BlockchainClient {
  Future<String> broadcastTransaction(String signedTransactionHex);
}
