class EstimateEnergyCostUseCase {
  final double ratePerKwh;

  const EstimateEnergyCostUseCase({required this.ratePerKwh});

  double call({required double energyKwh}) {
    return energyKwh * ratePerKwh;
  }
}
