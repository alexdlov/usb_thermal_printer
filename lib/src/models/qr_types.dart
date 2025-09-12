enum QRSizeType {
  size1(49), // 1
  size2(50), // 2
  size3(51), // 3
  size4(52), // 4
  size5(53), // 5
  size6(54), // 6
  size7(55), // 7
  size8(56); // 8

  final int value;
  const QRSizeType(this.value);
}

enum QRCorrectionLevel {
  L(48), // 0
  M(49), // 1
  Q(50), // 2
  H(51); // 3

  final int value;
  const QRCorrectionLevel(this.value);
}
