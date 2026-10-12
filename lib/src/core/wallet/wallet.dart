abstract class Wallet<T> {
  Future<List<T>> getAddresses();
  Future<T> generateAddress(String displayName);
  Future<void> saveAddress(T address);
  Future<void> deleteAddress(T address);
}
